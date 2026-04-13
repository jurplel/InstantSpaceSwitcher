#!/bin/bash
# test_overlay_live.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="osascript -l JavaScript ${SCRIPT_DIR}/overlay_check.js"

dismiss() {
    osascript -e 'tell application "System Events" to key code 53'
    sleep 1.0
}

trigger_expose() {
    # item -3 is show all windows on my system
    osascript <<'AS'
tell application "System Events"
    tell process "Dock"
        set finderIcon to UI element "Finder" of list 1
        perform action "AXShowMenu" of finderIcon
        delay 0.5
        tell menu 1 of finderIcon
            click menu item -3
        end tell
    end tell
end tell
AS
}

trigger_mc() {
    open -a "Mission Control"
}

# Ensure Finder has windows open
open -a "Finder" .
sleep 0.5
open -a "Finder" /tmp
sleep 0.5

echo "=== Normal state ==="
${CHECK}
echo ""

echo "=== App Exposé (Dock Item -2) ==="
trigger_expose
sleep 1.5
${CHECK}
dismiss
echo ""

echo "=== Mission Control ==="
trigger_mc
sleep 1.5
${CHECK}
dismiss
echo ""

echo "=== Normal state (after) ==="
${CHECK}
