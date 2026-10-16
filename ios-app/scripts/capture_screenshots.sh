#!/usr/bin/env bash
# Regenerates the iOS user guide's screenshots (docs/ios-guide/images/) by
# running the UI test walkthrough against the demo matrix and exporting the
# screenshots it attaches.
#
#   ios-app/scripts/capture_screenshots.sh ["iPhone 17 Pro"]
#
# Run from anywhere; needs Xcode 26+. Light/dark follows the simulator's
# appearance -- the committed guide images are dark mode.
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/ios-guide/images"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl ui "$DEVICE" appearance dark
# Clean status bar (9:41, full battery) so screenshots don't date.
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode notSupported

xcodebuild test \
  -project "$ROOT/ios-app/HDMIMatrix.xcodeproj" \
  -scheme HDMIMatrix \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -only-testing:HDMIMatrixUITests/HDMIMatrixUITests/testWalkthrough \
  -resultBundlePath "$WORK/run.xcresult" \
  -quiet

xcrun xcresulttool export attachments --path "$WORK/run.xcresult" --output-path "$WORK/attachments"

mkdir -p "$OUT"
python3 - "$WORK/attachments" "$OUT" <<'EOF'
import json, shutil, sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
count = 0
for test in json.loads((src / "manifest.json").read_text()):
    for att in test.get("attachments", []):
        # suggestedHumanReadableName looks like "01-routing_0_<uuid>.png"
        name = att["suggestedHumanReadableName"].split("_")[0]
        shutil.copy(src / att["exportedFileName"], out / f"{name}.png")
        count += 1
print(f"wrote {count} screenshots to {out}")
EOF

# Full device resolution is ~1 MB a shot; guide width is plenty.
for f in "$OUT"/*.png; do sips --resampleWidth 590 "$f" >/dev/null; done

xcrun simctl status_bar "$DEVICE" clear
