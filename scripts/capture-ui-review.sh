#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:-dist/UrzasOculus.app}"
OUTPUT_DIR="${2:-screenshots/ui-review}"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/UrzasOculus"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "App executable not found: $APP_EXECUTABLE" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png
if command -v screenresolution >/dev/null 2>&1; then
  screenresolution set 1600x1200 || echo "Display resize unavailable; proceeding with current resolution."
fi
URZAS_OCULUS_UI_REVIEW=cockpit "$APP_EXECUTABLE" &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 30); do
  if osascript -e 'tell application "System Events" to exists process "UrzasOculus"' 2>/dev/null | grep -q true; then break; fi
  sleep 1
done
sleep 4
BOUNDS="$(osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "UrzasOculus"
    set frontmost to true
    if (count of windows) is 0 then error "Urza's Oculus window did not appear"
    set b to bounds of front window
    return (item 1 of b) & "," & (item 2 of b) & "," & ((item 3 of b) - (item 1 of b)) & "," & ((item 4 of b) - (item 2 of b))
  end tell
end tell
APPLESCRIPT
)"
# Capture the full desktop; the app is foregrounded above. Avoid fragile AX window bounds.
screencapture -x "$OUTPUT_DIR/draft-cockpit.png"
test -s "$OUTPUT_DIR/draft-cockpit.png"
echo "Screenshot captured: $OUTPUT_DIR/draft-cockpit.png"
