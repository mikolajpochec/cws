#!/bin/sh
# Renders docs/hero.html to docs/hero.png (2x) with headless Chrome.
set -e
cd "$(dirname "$0")"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1240,800 --screenshot="$PWD/hero.png" "file://$PWD/hero.html" 2>/dev/null
echo "wrote $PWD/hero.png"
