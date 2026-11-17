#!/bin/bash
# Restart the installed menu bar app — used after `build.sh --install`.
set -euo pipefail
APP="${HERDRAPPBAR_APP:-$HOME/Applications/HerdrAppBar.app}"

if [ ! -d "$APP" ]; then
    echo "HerdrAppBar is not installed at $APP. Run scripts/build.sh --install first." >&2
    exit 1
fi

pkill -x HerdrAppBar >/dev/null 2>&1 || true
sleep 1
open -g "$APP"
echo "Restarted HerdrAppBar"
