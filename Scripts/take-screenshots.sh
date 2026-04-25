#!/usr/bin/env bash
# Capture launch screenshots from the *real* running ActivityManager.app —
# real timeline, real audit log, real settings. AppleScript clicks each
# sidebar section by accessibility name; `screencapture -R` crops to the
# main window's frame.
#
# Requires:
#   * ActivityManager.app installed at /Applications/ (or APP_PATH override).
#   * Accessibility permission granted to whatever process runs this script
#     (Terminal, iTerm, or your editor's integrated shell). System Settings →
#     Privacy & Security → Accessibility → add and enable.
#
# Output: docs/launch/assets/screenshots/<NN>-<section>.png (1080p PNGs)

set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${APP_PATH:-/Applications/ActivityManager.app}"
APP_NAME="ActivityManager"
OUT_DIR="docs/launch/assets/screenshots"
SETTLE_MS="${SETTLE_MS:-700}"  # ms to wait after each click before capture

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ $APP_PATH not found." >&2
    echo "  Build the app first (./Scripts/build-release.sh), drag to /Applications," >&2
    echo "  or set APP_PATH=/full/path/to/ActivityManager.app" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "» Launching $APP_NAME..."
open -a "$APP_PATH"

# Wait for the main window to register (the app boots into the menu-bar extra
# but the Window scene may need a beat to materialize).
sleep 2

# If the main window isn't already showing, open it via the menu-bar extra's
# "Open ActivityManager" command (added by SwiftUI for any Window scene).
osascript <<EOF || true
tell application "System Events"
    tell process "$APP_NAME"
        if not (exists window 1) then
            click menu bar item 1 of menu bar 2
            delay 0.5
            try
                click menu item "Open ActivityManager" of menu 1 of menu bar item 1 of menu bar 2
            end try
        end if
        set frontmost to true
    end tell
end tell
EOF

sleep 1

# Each entry: "<filename>|<sidebar row title>"
sections=(
    "01-overview.png|Overview"
    "02-processes.png|Processes"
    "03-timeline.png|Timeline"
    "04-rules.png|Rules"
    "05-insights.png|Insights"
    "06-settings.png|Settings"
)

# Read frontmost window bounds (origin x,y + size w,h) so screencapture -R
# crops to just our window. Falls back to whole screen if AX denied.
read_window_bounds() {
    osascript <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        try
            set frontmost to true
            set p to position of window 1
            set s to size of window 1
            return ((item 1 of p) as integer) & "," & ((item 2 of p) as integer) & "," & ((item 1 of s) as integer) & "," & ((item 2 of s) as integer)
        on error
            return "AX_DENIED"
        end try
    end tell
end tell
EOF
}

click_sidebar() {
    local label="$1"
    osascript <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        set frontmost to true
        try
            -- Sidebar is an outline / list inside a NavigationSplitView.
            -- Walk the AX tree by description; SwiftUI surfaces sidebar rows
            -- as static text inside outline rows.
            click (first static text of window 1 whose value is "$label")
        on error errMsg
            log "click failed for $label: " & errMsg
        end try
    end tell
end tell
EOF
}

settle() {
    # Convert SETTLE_MS to seconds for `sleep`.
    awk -v ms="$SETTLE_MS" 'BEGIN { printf "%.3f", ms/1000 }' | xargs sleep
}

for entry in "${sections[@]}"; do
    file="${entry%%|*}"
    label="${entry##*|}"
    echo "» $label → $OUT_DIR/$file"
    click_sidebar "$label"
    settle

    bounds="$(read_window_bounds | tr -d ' ')"
    if [[ "$bounds" == "AX_DENIED" || -z "$bounds" ]]; then
        echo "  ! Accessibility denied; capturing the whole screen." >&2
        screencapture -o -x "$OUT_DIR/$file"
    else
        screencapture -o -x -R "$bounds" "$OUT_DIR/$file"
    fi
done

echo
echo "✓ Wrote ${#sections[@]} screenshots to $OUT_DIR/"
echo "  Review them, then commit. Re-run anytime — destination files are overwritten."
