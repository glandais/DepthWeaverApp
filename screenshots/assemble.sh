#!/usr/bin/env bash
#
# Third step of the App Store screenshots: turn Koubou's renders into the set
# `asc screenshots upload` reads.
#
#   1. ./scripts/screenshots.sh                      -> screenshots/flat/<device>/<locale>/NN-*.png
#   2. kou generate screenshots/koubou/<device>.yaml
#                                                    -> screenshots/koubou/out/<device>/<locale>/<frame>/NN-*.png
#   3. ./screenshots/assemble.sh                     -> screenshots/<display type>/<locale>/NN-*.png
#
# Koubou writes a folder level App Store Connect does not know (the frame
# name): it is flattened, whatever the new render does not replace is removed
# from the destination — an old naming would otherwise go up with the new set —
# and a set the upload would reject is refused.
#
# Checks, all blocking:
#   - the exact size of the display type (1242x2688, 2048x2732, 2880x1800)
#   - no alpha channel — ASC answers IMAGE_ALPHA_NOT_ALLOWED, and
#     `asc screenshots validate` does NOT see it (see screenshots/README.md)
#   - not empty, and not much lighter than the same card in the other
#     language: a blank or half-painted render is light, not absent
#   - not heavier than 10 MB (a conservative ceiling, see CEILING)
#   - `asc screenshots validate` per locale on top, when asc is installed
#     (local check only: it reads the files, it sends nothing)
#
# Usage: ./screenshots/assemble.sh [--keep-stale] [--no-validate]
#
# Written for macOS's /bin/bash 3.2. The per-file checks are in the embedded
# Python.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="screenshots/koubou/out"

keep_stale=0
run_validate=1
for arg in "$@"; do
  case "$arg" in
    --keep-stale)  keep_stale=1 ;;
    --no-validate) run_validate=0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

# device -> App Store Connect display type, which names the destination.
display_type_for() {
  case "$1" in
    iphone) echo "IPHONE_65" ;;
    ipad)   echo "IPAD_PRO_3GEN_129" ;;
    mac)    echo "APP_DESKTOP" ;;
    *) red "unknown device under $OUT: $1"; exit 1 ;;
  esac
}

[ -d "$OUT" ] || { red "no render under $OUT — run: kou generate screenshots/koubou/iphone.yaml"; exit 1; }

devices=$(find "$OUT" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
[ -n "$devices" ] || { red "no device under $OUT"; exit 1; }

copied=0
for device in $devices; do
  type=$(display_type_for "$device")
  locales=$(find "$OUT/$device" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
  bold "$device -> screenshots/$type: $(echo "$locales" | tr '\n' ' ')"
  for loc in $locales; do
    # out/<device>/<locale>/<frame>/NN-*.png: exactly one frame folder expected.
    nframe=$(find "$OUT/$device/$loc" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [ "$nframe" != "1" ]; then
      red "FAILED $device/$loc: one frame folder expected under $OUT/$device/$loc, found $nframe"
      exit 1
    fi
    framedir=$(find "$OUT/$device/$loc" -mindepth 1 -maxdepth 1 -type d)
    npng=$(find "$framedir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
    [ "$npng" != "0" ] || { red "FAILED $device/$loc: no PNG in $framedir"; exit 1; }

    dst="screenshots/$type/$loc"
    mkdir -p "$dst"
    if [ "$keep_stale" -eq 0 ]; then
      for existing in "$dst"/*.png; do
        [ -e "$existing" ] || continue
        base=$(basename "$existing")
        if [ ! -e "$framedir/$base" ]; then
          rm "$existing"
          echo "  removed (stale) $dst/$base"
        fi
      done
    fi
    for src in "$framedir"/*.png; do
      cp "$src" "$dst/$(basename "$src")"
      copied=$((copied + 1))
    done
  done
done
bold "$copied files copied"

# ---------------------------------------------------------------- checks
python3 - <<'PY' || exit 1
import os, statistics, subprocess, sys

SETS = {"IPHONE_65": (1242, 2688), "IPAD_PRO_3GEN_129": (2048, 2732), "APP_DESKTOP": (2880, 1800)}
FLOOR = 0.50   # of the median size of the same card in the other languages
# A conservative ceiling, not a documented App Store Connect limit: the cards
# weigh 1 to 5 MB, so one past this is a render gone wrong (an uncompressed or
# oversized canvas) and would only slow the upload.
CEILING = 10 * 1024 * 1024

fail, checked = [], 0
for kind, expect in SETS.items():
    root = os.path.join("screenshots", kind)
    if not os.path.isdir(root):
        continue
    files = [(loc, name, os.path.join(root, loc, name))
             for loc in sorted(os.listdir(root)) if os.path.isdir(os.path.join(root, loc))
             for name in sorted(os.listdir(os.path.join(root, loc))) if name.endswith(".png")]
    by_card = {}
    for _, name, path in files:
        by_card.setdefault(name, []).append(os.path.getsize(path))
    median = {k: statistics.median(v) for k, v in by_card.items()}
    for loc, name, path in files:
        checked += 1
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", path],
                             capture_output=True, text=True).stdout
        got = {}
        for line in out.splitlines():
            if ":" in line:
                k, _, v = line.strip().partition(":")
                got[k.strip()] = v.strip()
        w, h = got.get("pixelWidth"), got.get("pixelHeight")
        where = f"{kind}/{loc}/{name}"
        if (w, h) != (str(expect[0]), str(expect[1])):
            fail.append(f"{where}: {w}x{h}, expected {expect[0]}x{expect[1]}")
        if got.get("hasAlpha") != "no":
            fail.append(f"{where}: alpha channel (ASC: IMAGE_ALPHA_NOT_ALLOWED)")
        size = os.path.getsize(path)
        if size == 0:
            fail.append(f"{where}: empty")
        elif size > CEILING:
            fail.append(f"{where}: {size} B, over the {CEILING} B ceiling")
        elif size < FLOOR * median[name]:
            fail.append(f"{where}: {size} B, under {FLOOR:.0%} of the {int(median[name])} B "
                        f"median of {name}")

print(f"{checked} files checked")
for f in fail:
    print("FAILED " + f)
sys.exit(1 if fail or not checked else 0)
PY

if [ "$run_validate" -eq 1 ]; then
  if command -v asc >/dev/null 2>&1; then
    for device in $devices; do
      type=$(display_type_for "$device")
      for dir in screenshots/"$type"/*/; do
        echo "asc screenshots validate — $type/$(basename "$dir")"
        asc screenshots validate --path "./$dir" --device-type "$type" >/dev/null
      done
    done
  else
    echo "asc not on PATH — per-locale validation skipped"
  fi
fi

bold "OK — screenshots/<display type>/<locale>/ are ready to upload"
