#!/usr/bin/env python3
"""cws search-session: fuzzy-search Claude Code sessions across workspaces.

usage: search_session.py [-n N] [--color] -- <keywords...>
workspaces arrive on stdin, one per line: name|configDir|color

Sessions live at <configDir>/projects/<encoded-cwd>/<sessionId>.jsonl (the
subagent transcripts in nested dirs are skipped). From each transcript we pull
titles (custom/ai title, agent name, summary), cwd, git branch, timestamps and
the plain text of user + assistant messages (tool calls/results skipped).
Extraction is cached per file (keyed by mtime+size) in $CWS_ROOT/.search-cache
so only new or changed transcripts get re-read.
"""
import argparse
import difflib
import glob
import json
import os
import pickle
import re
import sys
import time
from datetime import datetime

CACHE_VERSION = 2
TEXT_CAP = 400_000          # chars of message text kept per session
WORD_RE = re.compile(r"[a-z0-9][a-z0-9_\-.]*[a-z0-9]|[a-z0-9]")

# field -> weight; titles and prompts you typed matter more than bulk text
WEIGHTS = {"title": 10.0, "project": 6.0, "prompt": 5.0, "branch": 3.0, "text": 2.0}


def extract(path):
    s = {"titles": [], "cwd": "", "branch": "", "first": "", "last": "",
         "prompts": [], "text": [], "n_user": 0, "n_asst": 0}
    size = 0
    try:
        fp = open(path, "rb")
    except OSError:
        return None
    with fp:
        for raw in fp:
            if not raw.startswith(b"{"):
                continue
            try:
                o = json.loads(raw)
            except ValueError:
                continue
            t = o.get("type")
            ts = o.get("timestamp")
            if isinstance(ts, str):
                if not s["first"]:
                    s["first"] = ts
                s["last"] = ts
            if t == "custom-title" and o.get("customTitle"):
                s["titles"].insert(0, o["customTitle"])
            elif t == "ai-title" and o.get("aiTitle"):
                s["titles"].append(o["aiTitle"])
            elif t == "agent-name" and o.get("agentName"):
                s["titles"].append(o["agentName"])
            elif t == "summary" and o.get("summary"):
                s["titles"].append(o["summary"])
            elif t in ("user", "assistant"):
                if not s["cwd"] and o.get("cwd"):
                    s["cwd"] = o["cwd"]
                if not s["branch"] and o.get("gitBranch") and o["gitBranch"] != "HEAD":
                    s["branch"] = o["gitBranch"]
                if o.get("isMeta") or o.get("isSidechain"):
                    continue
                c = (o.get("message") or {}).get("content")
                parts = []
                if isinstance(c, str):
                    parts.append(c)
                elif isinstance(c, list):
                    for b in c:
                        if isinstance(b, dict) and b.get("type") == "text":
                            parts.append(b.get("text") or "")
                txt = "\n".join(p for p in parts if p).strip()
                if not txt:
                    continue
                if t == "user":
                    # skip slash-command wrappers / hook noise
                    if txt.startswith("<") and ("command-" in txt[:40] or "local-command" in txt[:40]):
                        continue
                    s["n_user"] += 1
                    s["prompts"].append(txt[:2000])
                else:
                    s["n_asst"] += 1
                if size < TEXT_CAP:
                    s["text"].append(txt)
                    size += len(txt)
    # dedupe titles, keep order
    seen, titles = set(), []
    for x in s["titles"]:
        if x not in seen:
            seen.add(x)
            titles.append(x)
    s["titles"] = titles
    s["text"] = "\n".join(s["text"])[:TEXT_CAP]
    s["prompts"] = s["prompts"][:50]
    return s


def load_cache(path):
    try:
        with open(path, "rb") as fp:
            data = pickle.load(fp)
        if data.get("v") == CACHE_VERSION:
            return data["files"]
    except Exception:
        pass
    return {}


def save_cache(path, files):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "wb") as fp:
            pickle.dump({"v": CACHE_VERSION, "files": files}, fp, protocol=pickle.HIGHEST_PROTOCOL)
        os.replace(tmp, path)
    except OSError:
        pass


def gather(workspaces, cache_path):
    cache = load_cache(cache_path)
    # keep entries of workspaces not scanned this run (-w subset)
    roots = tuple(os.path.join(cfg, "projects", "") for _, cfg, _ in workspaces)
    fresh = {p: v for p, v in cache.items() if not p.startswith(roots)}
    sessions = []
    for ws, cfg, color in workspaces:
        for path in glob.glob(os.path.join(glob.escape(cfg), "projects", "*", "*.jsonl")):
            try:
                st = os.stat(path)
            except OSError:
                continue
            key = (st.st_mtime_ns, st.st_size)
            hit = cache.get(path)
            if hit and hit[0] == key:
                s = hit[1]
            else:
                s = extract(path)
                if s is None:
                    continue
            fresh[path] = (key, s)
            if not (s["n_user"] or s["titles"]):
                continue  # empty/aborted session
            sessions.append((ws, cfg, color, path, s))
    if fresh != cache:
        save_cache(cache_path, fresh)
    return sessions


def words(text):
    return WORD_RE.findall(text.lower())


class Matcher:
    """scores one keyword against a text field: exact word > prefix >
    substring > typo-tolerant (difflib) word match."""

    def __init__(self, kw):
        self.kw = kw
        self.word_re = re.compile(r"(?<![a-z0-9])" + re.escape(kw) + r"(?![a-z0-9])")
        self.prefix_re = re.compile(r"(?<![a-z0-9])" + re.escape(kw))
        self.fuzzy_cache = {}

    def fuzzy_word(self, w):
        r = self.fuzzy_cache.get(w)
        if r is None:
            kw = self.kw
            if abs(len(w) - len(kw)) > max(1, len(kw) // 3) or len(kw) < 4:
                r = 0.0
            else:
                ratio = difflib.SequenceMatcher(None, kw, w).ratio()
                r = ratio if ratio >= 0.8 else 0.0
            self.fuzzy_cache[w] = r
        return r

    def score(self, low, vocab):
        """low: lowercased field text; vocab: set of its words.
        returns (quality 0..1, occurrences)."""
        n = len(self.word_re.findall(low))
        if n:
            return 1.0, n
        n = len(self.prefix_re.findall(low))
        if n:
            return 0.8, n
        n = low.count(self.kw)
        if n:
            return 0.6, n
        best = 0.0
        for w in vocab:
            f = self.fuzzy_word(w)
            if f > best:
                best = f
                if best >= 0.95:
                    break
        return (best * 0.6, 1) if best else (0.0, 0)


def score_session(s, matchers, phrase):
    fields = {
        "title": " \n".join(s["titles"]),
        "project": s["cwd"].replace("/", " ").replace("-", " ") + " " + s["cwd"],
        "prompt": "\n".join(s["prompts"]),
        "branch": s["branch"],
        "text": s["text"],
    }
    total, hits, matched_all = 0.0, {}, True
    lows = {k: v.lower() for k, v in fields.items()}
    vocabs = {}
    for m in matchers:
        best_kw = 0.0
        for f, low in lows.items():
            if not low:
                continue
            if f not in vocabs:
                vocabs[f] = set(words(low)) if f != "text" else None
            vocab = vocabs[f]
            if vocab is None:
                # fuzzy over bulk text is too slow; only exact/prefix/substring
                q, n = m.score(low, ())
            else:
                q, n = m.score(low, vocab)
            if not q:
                continue
            # diminishing returns on repeat mentions
            sc = WEIGHTS[f] * q * (1.0 + min(n, 30) ** 0.5 / 3.0)
            best_kw += sc
            hits.setdefault(f, []).append(m.kw)
        if not best_kw:
            matched_all = False
        total += best_kw
    if total and len(matchers) > 1:
        if matched_all:
            total *= 1.5
        if phrase and any(phrase in lows[f] for f in ("title", "prompt", "text")):
            total *= 1.3
    return total, matched_all, hits


def snippet(text, kws, width=110):
    low = text.lower()
    pos = -1
    for kw in kws:
        pos = low.find(kw)
        if pos >= 0:
            break
    if pos < 0:
        return ""
    start = max(0, pos - width // 3)
    seg = " ".join(text[start:start + width].split())
    return ("…" if start else "") + seg + ("…" if start + width < len(text) else "")


def ago(ts):
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return ""
    d = time.time() - dt.timestamp()
    if d < 3600:
        return f"{max(1, int(d // 60))}m ago"
    if d < 86400:
        return f"{int(d // 3600)}h ago"
    if d < 86400 * 60:
        return f"{int(d // 86400)}d ago"
    return dt.astimezone().strftime("%Y-%m-%d")


def rgb(hexcolor):
    h = hexcolor.lstrip("#")
    if len(h) != 6:
        return None
    return f"{int(h[0:2], 16)};{int(h[2:4], 16)};{int(h[4:6], 16)}"


def main():
    ap = argparse.ArgumentParser(prog="cws search-session")
    ap.add_argument("-n", "--limit", type=int, default=10)
    ap.add_argument("--color", action="store_true")
    ap.add_argument("keywords", nargs="+")
    a = ap.parse_args()

    workspaces = []
    for line in sys.stdin:
        parts = line.rstrip("\n").split("|")
        if len(parts) >= 2 and parts[0]:
            workspaces.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ""))

    phrase = " ".join(a.keywords).lower().strip()
    kws = [k for k in words(phrase)] or [phrase]
    kws = list(dict.fromkeys(kws))
    matchers = [Matcher(k) for k in kws]

    root = os.environ.get("CWS_ROOT") or os.path.expanduser("~/.config/claude-workspaces")
    sessions = gather(workspaces, os.path.join(root, ".search-cache"))

    results = []
    for ws, cfg, color, path, s in sessions:
        sc, all_, hits = score_session(s, matchers, phrase)
        if sc > 0:
            results.append((all_, sc, s.get("last") or "", ws, color, path, s, hits))
    # sessions matching every keyword first, then score, then recency
    results.sort(key=lambda r: (r[0], r[1], r[2]), reverse=True)

    if not results:
        print(f"no sessions match '{phrase}' in {len(sessions)} session(s) across "
              f"{', '.join(w[0] for w in workspaces)}", file=sys.stderr)
        return 1

    C = a.color
    bold = (lambda x: f"\033[1m{x}\033[0m") if C else (lambda x: x)
    dim = (lambda x: f"\033[2m{x}\033[0m") if C else (lambda x: x)
    home = os.path.expanduser("~")
    shown = results[:a.limit]
    for i, (all_, sc, last, ws, color, path, s, hits) in enumerate(shown, 1):
        sid = os.path.basename(path)[:-6]
        title = s["titles"][0] if s["titles"] else (s["prompts"][0] if s["prompts"] else "(untitled)")
        idea = re.search(r"^IDEA:\s*(.+)$", title, re.M)  # Ideas-app agent boilerplate
        if idea:
            title = idea.group(1)
        title = " ".join(title.split())
        if len(title) > 90:
            title = title[:89] + "…"
        wsl = f"[{ws}]"
        c = rgb(color) if C and color else None
        if c:
            wsl = f"\033[38;2;{c}m{wsl}\033[0m"
        cwd = s["cwd"] or "?"
        cwd_disp = "~" + cwd[len(home):] if cwd.startswith(home) else cwd
        meta = f"{cwd_disp}" + (f" ({s['branch']})" if s["branch"] else "") + \
               f" · {ago(last)} · {s['n_user']} prompt(s)"
        print(f"{i:>2}. {wsl} {bold(title)}  {dim(f'score {sc:.0f}')}")
        print(f"    {dim(meta)}")
        if "title" not in hits:
            for f in ("prompt", "text"):
                if f in hits:
                    src = "\n".join(s["prompts"]) if f == "prompt" else s["text"]
                    sn = snippet(src, hits[f])
                    if sn:
                        print(f"    “{sn}”")
                        break
        resume = f"cws {ws} --resume {sid}"
        if s["cwd"]:
            q = s["cwd"] if re.fullmatch(r"[\w./@+-]+", s["cwd"]) else "'" + s["cwd"].replace("'", "'\\''") + "'"
            resume = f"cd {q} && {resume}"
        print(f"    {dim('→')} {resume}")
    if len(results) > len(shown):
        print(dim(f"… {len(results) - len(shown)} more match(es); use -n to show more"))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
