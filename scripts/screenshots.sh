#!/usr/bin/env bash
#
# The raw material of the App Store screenshots: every screen, in every
# language, on the iPhone then the iPad (and the Mac on request), without a
# single tap.
#
# Builds the app in the `Screenshots` configuration (see project.yml), then
# launches it once per card and per language with the arguments that
# `ScreenshotMode` reads (DepthWeaver/Screenshots/). One launch per capture:
# nothing depends on a button label, which changes from one language to the
# next.
#
# Output: screenshots/flat/<device>/<locale>/NN-name.png — the simulator (or
# Mac window) capture at full resolution, alpha channel flattened. These are
# not the uploaded files yet: Koubou turns them into cards (frame and title),
# and screenshots/assemble.sh files them where `asc` reads them. See
# screenshots/README.md.
#
# Usage: ./scripts/screenshots.sh [--iphone] [--ipad] [--mac] [locale ...]
#        (default: --iphone --ipad, in en-US and fr-FR)
#
# One simulator booted at a time (see scripts/sim-config.sh): the iPad only
# boots once every other simulator is down, and is shut down at the end, even
# on an error; the repository's iPhone is booted again if it was up.
#
# --mac launches the macOS build itself and captures its window with
# `screencapture -l`: the window comes to the front, so leave the Mac alone
# while it runs. The terminal needs the Screen Recording permission.
#
# Written for macOS's /bin/bash 3.2: no mapfile, no associative arrays.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sim-config.sh
source scripts/sim-capture.sh

OUT_ROOT="screenshots/flat"

# ScreenshotMode screen -> file, in upload order (files go up in alphabetical
# order, hence the numbers). Same seven screens as the listing's first set.
CARDS=(
  "hero:01-hero"
  "source:02-source"
  "depth3d:03-depth-3d"
  "model:04-model"
  "pattern:05-pattern"
  "adjust:06-adjust"
  "tune:07-tune"
)

# The Mac has one window: the canvas and its inspector.
MAC_CARDS=(
  "hero:01-hero"
  "pattern:02-pattern"
  "tune:03-tune"
)

# Left on screen once the marker is there: the marker already waits for the
# content plus ScreenshotMode.settle; this covers the last frame reaching the
# simulator's framebuffer on a loaded machine.
SETTLE=2

parse_capture_args "$@"

# Expected width/height ratio of a capture, within 2 %: it proves the capture
# comes from the right device, and therefore fits the Koubou frame (iPhone 17
# Pro Max, 1320 x 2868; iPad Pro 13 M4).
ratio_for() {
  case "$1" in
    iphone) echo "1320/2868" ;;
    ipad)   echo "2064/2752" ;;
    mac)    echo "1440/900" ;;
  esac
}

wants_ios=0
wants_mac=0
for device in "${devices[@]}"; do
  case "$device" in
    iphone|ipad) wants_ios=1 ;;
    mac)         wants_mac=1 ;;
  esac
done

MAC_PID=""
cleanup() {
  if [ -n "$MAC_PID" ]; then kill "$MAC_PID" >/dev/null 2>&1 || true; fi
  restore_simulators
}
trap cleanup EXIT

[ "$wants_ios" = 0 ] || build_capture_app ios
[ "$wants_mac" = 0 ] || build_capture_app mac

# ---------------------------------------------------------------- iOS

capture_ios() {
  local screen="$1" locale="$2" file="$3"
  launch_staged "$screen" "$locale"
  sleep "$SETTLE"
  xcrun simctl io "$CURRENT" screenshot --type=png "$file" >/dev/null 2>&1
}

# ---------------------------------------------------------------- macOS

# The app prints `screenshot-ready <screen> <window number>` on stdout once the
# screen is in place. (It also writes the marker file in its sandbox container,
# but app data protection keeps other processes from reading it.)
capture_mac() {
  local screen="$1" locale="$2" file="$3" log window waited=0
  pkill -f "$MAC_APP/Contents/MacOS/DepthWeaver" >/dev/null 2>&1 || true
  log="$(mktemp -t depthweaver-capture)"
  "$MAC_APP/Contents/MacOS/DepthWeaver" \
    -screenshotMode YES \
    -screenshotScreen "$screen" \
    -ApplePersistenceIgnoreState YES \
    -AppleLanguages "(${locale%%-*})" \
    -AppleLocale "$(apple_locale_for "$locale")" >"$log" 2>/dev/null &
  MAC_PID=$!
  until grep -q '^screenshot-ready ' "$log"; do
    sleep 0.5
    waited=$((waited + 1))
    if ! kill -0 "$MAC_PID" 2>/dev/null; then
      echo "✖ mac $screen: the app exited before it was ready" >&2
      exit 1
    fi
    if [ "$waited" -ge $((READY_TIMEOUT * 2)) ]; then
      echo "✖ mac $screen: the app did not report ready within ${READY_TIMEOUT} s" >&2
      exit 1
    fi
  done
  window="$(awk '/^screenshot-ready /{print $3; exit}' "$log")"
  rm -f "$log"
  [ -n "$window" ] || { echo "✖ mac $screen: no window number reported" >&2; exit 1; }
  sleep "$SETTLE"
  # -o: no shadow, -x: no sound. The window's rounded corners come out
  # transparent; they are flattened below and the template rounds them again.
  if ! screencapture -o -x -l "$window" "$file"; then
    echo "✖ mac $screen: screencapture failed — does the terminal have the" >&2
    echo "  Screen Recording permission (System Settings › Privacy & Security)?" >&2
    exit 1
  fi
  kill "$MAC_PID" >/dev/null 2>&1 || true
  wait "$MAC_PID" 2>/dev/null || true
  MAC_PID=""
}

# ---------------------------------------------------------------- captures

for device in "${devices[@]}"; do
  if [ "$device" = mac ]; then
    echo "▸ mac: $(sw_vers -productVersion)"
    for locale in "${locales[@]}"; do
      dir="$OUT_ROOT/mac/$locale"
      mkdir -p "$dir"
      rm -f "$dir"/*.png
      echo "▸ mac · $locale"
      for entry in "${MAC_CARDS[@]}"; do
        capture_mac "${entry%%:*}" "$locale" "$dir/${entry#*:}.png"
        echo "   · ${entry#*:}"
      done
    done
    continue
  fi

  udid=$(udid_for "$device")
  echo "▸ $device: ${udid}"
  use_simulator "$udid"
  install_fresh

  for locale in "${locales[@]}"; do
    prepare_locale "$locale"
    dir="$OUT_ROOT/$device/$locale"
    mkdir -p "$dir"
    rm -f "$dir"/*.png
    echo "▸ $device · $locale"
    for entry in "${CARDS[@]}"; do
      capture_ios "${entry%%:*}" "$locale" "$dir/${entry#*:}.png"
      echo "   · ${entry#*:}"
    done
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
done

# ---------------------------------------------------------------- checks

# Different screens cannot give the same image twice. When they do, the app
# that answered is not the one installed: a Debug build installed over it
# under the same bundle id (./scripts/xcb.sh run) ignores -screenshotScreen.
echo "▸ distinct screens per set"
for device in "${devices[@]}"; do
  for locale in "${locales[@]}"; do
    dup="$(md5 -q "$OUT_ROOT/$device/$locale"/*.png | sort | uniq -d | wc -l | tr -d ' ')"
    if [ "$dup" != "0" ]; then
      echo "✖ $device/$locale: identical captures — the app that ran is not the" >&2
      echo "  one installed. Nothing else may drive the simulator during a" >&2
      echo "  capture (./scripts/xcb.sh run in particular)." >&2
      exit 1
    fi
  done
done

echo "▸ shape and alpha channel"
for device in "${devices[@]}"; do
  python3 - "$OUT_ROOT/$device" "$(ratio_for "$device")" "${locales[@]}" <<'PY'
import pathlib, sys
from PIL import Image

root, ratio = pathlib.Path(sys.argv[1]), sys.argv[2]
w, h = (int(x) for x in ratio.split("/"))
TARGET, TOLERANCE = w / h, 0.02
for locale in sys.argv[3:]:
    for src in sorted((root / locale).glob("*.png")):
        im = Image.open(src)
        skew = abs((im.width / im.height) / TARGET - 1)
        if skew > TOLERANCE:
            sys.exit(f"{src} is {im.width}x{im.height}, {skew:.0%} off the expected "
                     f"ratio ({ratio}): not the device of the Koubou frame.")
        # App Store Connect refuses any alpha channel (IMAGE_ALPHA_NOT_ALLOWED),
        # and `asc screenshots validate` does not see it. The rounded corners
        # of an iPhone capture (and of a Mac window) are transparent: black
        # behind them, like the device frame.
        if "A" in im.getbands() or im.mode in ("LA", "P"):
            im = im.convert("RGBA")
            bg = Image.new("RGB", im.size, (0, 0, 0))
            bg.paste(im, mask=im.getchannel("A"))
            im = bg
        else:
            im = im.convert("RGB")
        im.save(src, "PNG", optimize=True)
        print(f"   · {src} ({im.width}x{im.height})")
PY
done

echo "▸ done: $OUT_ROOT/<device>/<locale>/NN-*.png, ${#locales[@]} language(s) × ${#devices[@]} device(s)."
echo "▸ next: kou generate screenshots/koubou/iphone.yaml (and ipad.yaml, mac.yaml),"
echo "  then ./screenshots/assemble.sh."
