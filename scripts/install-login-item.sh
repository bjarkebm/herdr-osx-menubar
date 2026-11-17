#!/bin/bash
# Install the "start at login" LaunchAgent for HerdrAppBar.
set -euo pipefail

APP="${HERDRAPPBAR_APP:-$HOME/Applications/HerdrAppBar.app}"
BINARY="$APP/Contents/MacOS/HerdrAppBar"
LABEL="dev.herdr.appbar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$BINARY" ]; then
    echo "HerdrAppBar is not installed. Run scripts/build.sh --install first." >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$BINARY</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
PLISTEOF

# Reload so it takes effect now rather than at next login.
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true

echo "Installed login item: $PLIST"
echo "Verify with: launchctl print gui/$(id -u)/$LABEL"
