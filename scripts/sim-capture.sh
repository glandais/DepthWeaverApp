#!/usr/bin/env bash
#
# The simulator plumbing behind the App Store captures (scripts/screenshots.sh):
# arguments and locales, the app built in the `Screenshots` configuration, one
# simulator at a time, the system language and a clean status bar, and the
# launch of one screen in capture mode.
#
# Source it, do not execute it, after `cd` to the repository root and
# `source scripts/sim-config.sh`:
#
#   source scripts/sim-capture.sh
#   parse_capture_args "$@"      # -> devices=(iphone ipad), locales=(en-US fr-FR)
#   build_capture_app
#   for device in "${devices[@]}"; do use_simulator "$(udid_for "$device")"; … done
#
# Written for macOS's /bin/bash 3.2: no mapfile, no associative arrays.

BUNDLE_ID="io.github.glandais.depthweaver"
APP="${DERIVED_DATA}/Build/Products/Screenshots-iphonesimulator/DepthWeaver.app"
MAC_APP="${DERIVED_DATA}/Build/Products/Screenshots/DepthWeaver.app"

# A stereogram renders in a second or two in Debug; the first launch after an
# install, on a loaded Mac, has been seen to take minutes before the first
# frame. Past this, something went wrong.
READY_TIMEOUT="${DEPTHWEAVER_READY_TIMEOUT:-600}"

# ---------------------------------------------------------------- arguments

# [--iphone | --ipad | --mac] [locale ...] -> `devices` and `locales`. By
# default iPhone and iPad (the Mac is opt-in: it takes over the screen), in
# en-US and fr-FR.
parse_capture_args() {
  devices=()
  locales=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --iphone) devices+=(iphone) ;;
      --ipad)   devices+=(ipad) ;;
      --mac)    devices+=(mac) ;;
      -h|--help)
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      -*)       echo "✖ unknown option: $arg" >&2; exit 2 ;;
      *)        locales+=("$(check_locale "$arg")") ;;
    esac
  done
  [ "${#devices[@]}" -gt 0 ] || devices=(iphone ipad)
  [ "${#locales[@]}" -gt 0 ] || locales=(en-US fr-FR)
}

# App Store Connect locales name the output folders. Only the app's two
# languages exist: guessing would file one market under another's folder.
check_locale() {
  case "$1" in
    en-US|fr-FR) echo "$1" ;;
    *)
      echo "✖ unsupported locale \"$1\" (the app ships en-US and fr-FR)" >&2
      exit 2
      ;;
  esac
}

apple_locale_for() { echo "${1/-/_}"; }

udid_for() {
  case "$1" in
    iphone) sim_udid ;;
    ipad)   ipad_udid ;;
  esac
}

# ---------------------------------------------------------------- simulators

# Was the repository's iPhone booted on arrival? It is the only one brought
# back on exit: the iPad has no reason to stay up after a capture, even if it
# was before — bringing it back would make two simulators.
IPHONE_UDID=$(sim_udid)
IPHONE_WAS_BOOTED=0
xcrun simctl list devices booted | grep -q "$IPHONE_UDID" && IPHONE_WAS_BOOTED=1
CURRENT=""
# The current device's system language, given back on exit (see below).
SYSTEM_LANGUAGES_BEFORE=""
SYSTEM_LOCALE_BEFORE=""

# Puts the *system* of the current simulator in language `$1` / locale `$2`
# and restarts SpringBoard so that it takes it.
#
# The status bar is drawn by the system, which `-AppleLanguages` does not
# reach: the iPad writes the date there, in the system's language.
set_system_locale() {
  # `$1` may be a comma-separated list (the languages found on arrival).
  local languages
  IFS=',' read -r -a languages <<< "$1"
  sim_spawn defaults write -g AppleLanguages -array "${languages[@]}"
  sim_spawn defaults write -g AppleLocale -string "$2"
  sim_spawn launchctl stop com.apple.SpringBoard
  sleep 8
}

# `simctl spawn` on the current simulator, given up after SPAWN_TIMEOUT
# seconds: on a loaded Mac a single `defaults write` has been seen to hang for
# ten minutes. A missed system language only affects the iPad's status-bar
# date, which the capture check below does not depend on.
SPAWN_TIMEOUT="${DEPTHWEAVER_SPAWN_TIMEOUT:-90}"
sim_spawn() {
  perl -e 'alarm shift; exec @ARGV' "$SPAWN_TIMEOUT" \
    xcrun simctl spawn "$CURRENT" "$@" >/dev/null 2>&1 || true
}

# The simulator's system in the language of `$1` (an App Store Connect
# locale), then Apple's status bar: 9:41, a full battery, full signal — set
# again after every language change, which the SpringBoard restart clears.
prepare_locale() {
  set_system_locale "$1" "$(apple_locale_for "$1")"
  xcrun simctl status_bar "$CURRENT" override --time "9:41" \
    --batteryLevel 100 --batteryState discharging \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3
}

restore_simulators() {
  # A Mac-only run never touched a simulator: nothing to give back.
  [ -n "$CURRENT" ] || return 0
  if [ -n "$CURRENT" ]; then
    if [ -n "$SYSTEM_LANGUAGES_BEFORE" ] && [ -n "$SYSTEM_LOCALE_BEFORE" ]; then
      set_system_locale "$SYSTEM_LANGUAGES_BEFORE" "$SYSTEM_LOCALE_BEFORE"
    fi
    xcrun simctl status_bar "$CURRENT" clear >/dev/null 2>&1 || true
    xcrun simctl terminate "$CURRENT" "$BUNDLE_ID" >/dev/null 2>&1 || true
    if [ "$CURRENT" != "$IPHONE_UDID" ]; then
      echo "▸ shutting down the iPad"
      xcrun simctl shutdown "$CURRENT" >/dev/null 2>&1 || true
    fi
  fi
  if [ "$IPHONE_WAS_BOOTED" = 1 ] && [ "$CURRENT" != "$IPHONE_UDID" ]; then
    echo "▸ booting ${SIM_DEVICE} again, as it was before the capture"
    sim_boot "$IPHONE_UDID" || true
  fi
}

# Boots `$1` after shutting down every other simulator (`sim_boot` does it):
# one at a time.
use_simulator() {
  local target="$1"
  if [ -n "$CURRENT" ] && [ "$CURRENT" != "$target" ]; then
    # Leave the previous device as it was found before switching.
    if [ -n "$SYSTEM_LANGUAGES_BEFORE" ] && [ -n "$SYSTEM_LOCALE_BEFORE" ]; then
      set_system_locale "$SYSTEM_LANGUAGES_BEFORE" "$SYSTEM_LOCALE_BEFORE"
    fi
    xcrun simctl status_bar "$CURRENT" clear >/dev/null 2>&1 || true
  fi
  CURRENT="$target"
  sim_boot "$target"
  SYSTEM_LANGUAGES_BEFORE="$(perl -e 'alarm shift; exec @ARGV' "$SPAWN_TIMEOUT" \
    xcrun simctl spawn "$target" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"()' || true)"
  SYSTEM_LOCALE_BEFORE="$(perl -e 'alarm shift; exec @ARGV' "$SPAWN_TIMEOUT" \
    xcrun simctl spawn "$target" defaults read -g AppleLocale 2>/dev/null || true)"
}

# Uninstalls then installs the app: a fresh container, with no captured
# models and no settings left from an earlier run.
install_fresh() {
  xcrun simctl uninstall "$CURRENT" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$CURRENT" "$APP"
}

# ---------------------------------------------------------------- build

# `$1`: ios or mac.
build_capture_app() {
  local platform="$1" destination
  case "$platform" in
    ios) destination="$(sim_dest "$IPHONE_UDID")" ;;
    mac) destination="platform=macOS,arch=arm64" ;;
  esac
  echo "▸ building ($platform, Screenshots configuration)"
  # One simulator build serves every device of the same architecture: the
  # iPad installs the same product. The destination boots nothing.
  xcodebuild -project DepthWeaver.xcodeproj \
    -scheme DepthWeaver-Screenshots \
    -configuration Screenshots \
    -destination "$destination" \
    -derivedDataPath "$DERIVED_DATA" \
    build >/dev/null
  if [ "$platform" = ios ]; then
    [ -d "$APP" ] || { echo "✖ product not found: $APP" >&2; exit 1; }
  else
    [ -d "$MAC_APP" ] || { echo "✖ product not found: $MAC_APP" >&2; exit 1; }
  fi
}

# ---------------------------------------------------------------- launch

# The marker `ScreenshotMode` writes once the screen is in place.
ready_marker() {
  echo "$(xcrun simctl get_app_container "$CURRENT" "$BUNDLE_ID" data)/tmp/screenshot-ready"
}

# Waits until file `$1` exists and is not empty; `$2` names the screen.
wait_for_marker() {
  local marker="$1" screen="$2" waited=0
  until [ -s "$marker" ]; do
    sleep 0.5
    waited=$((waited + 1))
    if [ "$waited" -ge $((READY_TIMEOUT * 2)) ]; then
      echo "✖ $screen: the app did not report ready within ${READY_TIMEOUT} s" >&2
      exit 1
    fi
  done
}

# Launches the app on screen `$1`, in language `$2` (an App Store Connect
# locale), then waits for its marker. No fixed delay: render time varies a lot
# from one machine, and one load, to the next.
launch_staged() {
  local screen="$1" locale="$2" marker
  xcrun simctl terminate "$CURRENT" "$BUNDLE_ID" >/dev/null 2>&1 || true
  marker="$(ready_marker)"
  rm -f "$marker"
  xcrun simctl launch "$CURRENT" "$BUNDLE_ID" \
    -screenshotMode YES \
    -screenshotScreen "$screen" \
    -AppleLanguages "(${locale%%-*})" \
    -AppleLocale "$(apple_locale_for "$locale")" >/dev/null
  wait_for_marker "$marker" "$screen"
}
