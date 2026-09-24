#!/usr/bin/env bash
#
# The one simulator this repository uses, and no other.
#
# This Mac has limited resources: a booted simulator costs gigabytes of RAM and
# its device directory grows by gigabytes on disk. Everything that needs a
# destination resolves it here, so that no build boots a device nobody asked for.
#
# `iPhone 17 Pro Max` on iOS 26.5 is the pinned device for DepthWeaver: builds,
# runs, tests and screenshots. It is a large iPhone, the size App Store
# screenshots require. Do not use the `iPhone 18 Pro Max` (iOS 27.0) simulator:
# it runs badly on this Mac. `DEPTHWEAVER_SIM_DEVICE` switches device for a whole
# session; `DEPTHWEAVER_SIM_RUNTIME` picks the runtime when the name exists on
# several (default: iOS 26.5).
#
# Source it, do not execute it:  source "$(dirname "$0")/sim-config.sh"

SIM_DEVICE="${DEPTHWEAVER_SIM_DEVICE:-iPhone 17 Pro Max}"
SIM_RUNTIME="${DEPTHWEAVER_SIM_RUNTIME:-iOS 26.5}"
DERIVED_DATA="${DEPTHWEAVER_DERIVED_DATA:-.build/DerivedData}"

# Prints the UDID of $SIM_DEVICE, or explains what is available and fails.
# When the name exists on several runtimes, the one on $SIM_RUNTIME wins;
# otherwise the newest runtime is used.
sim_udid() {
  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name, preferred = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"]

def runtime_label(key):
    # com.apple.CoreSimulator.SimRuntime.iOS-27-0 -> "iOS 27.0"
    m = re.search(r"SimRuntime\.(\w+?)-(\d+(?:-\d+)*)$", key)
    return f"{m.group(1)} {m.group(2).replace(chr(45), chr(46))}" if m else key

def version(key):
    m = re.search(r"-(\d+(?:-\d+)*)$", key)
    return tuple(int(p) for p in m.group(1).split("-")) if m else ()

matches = [(runtime, device["udid"])
           for runtime in devices for device in devices[runtime]
           if device["name"] == name]
if not matches:
    sys.exit(1)
for runtime, udid in matches:
    if runtime_label(runtime) == preferred:
        print(udid)
        sys.exit(0)
print(max(matches, key=lambda m: version(m[0]))[1])
' "$SIM_DEVICE" "$SIM_RUNTIME") || {
    echo "sim-config: no available simulator named \"${SIM_DEVICE}\"." >&2
    echo "Available devices:" >&2
    xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in devices:
    for device in devices[runtime]:
        print("  " + device["name"] + "  (" + runtime.rsplit(".", 1)[-1] + ")")
' >&2
    echo "Create it in Xcode, or set DEPTHWEAVER_SIM_DEVICE." >&2
    return 1
  }
  echo "$udid"
}

# Shuts down every booted simulator except the given UDID: never two at once.
sim_shutdown_others() {
  local keep="$1" other
  for other in $(xcrun simctl list devices booted -j | python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        print(device["udid"])
'); do
    if [ "$other" != "$keep" ]; then
      echo "sim-config: shutting down other booted simulator ${other}" >&2
      xcrun simctl shutdown "$other" 2>/dev/null || true
    fi
  done
}

# Boots $SIM_DEVICE (or the given UDID) if needed, after shutting down any other
# booted simulator, and waits until it is ready. Idempotent.
sim_boot() {
  local udid="${1:-}"
  if [ -z "$udid" ]; then udid=$(sim_udid) || return 1; fi
  sim_shutdown_others "$udid"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

# The only -destination an iOS simulator xcodebuild in this repository may use.
sim_dest() {
  local udid="${1:-}"
  if [ -z "$udid" ]; then udid=$(sim_udid) || return 1; fi
  echo "platform=iOS Simulator,id=${udid}"
}

# The App Store screenshots iPad, and nothing else: the listing needs a 13-inch
# set. It is booted only for iPad screenshot captures, with the iPhone shut down
# before and brought back after: never two simulators at once.
IPAD_DEVICE="${DEPTHWEAVER_IPAD_DEVICE:-iPad Pro 13-inch (M4)}"

# Prints the UDID of the screenshots iPad, with the same messages as `sim_udid`.
ipad_udid() {
  SIM_DEVICE="$IPAD_DEVICE" sim_udid
}
