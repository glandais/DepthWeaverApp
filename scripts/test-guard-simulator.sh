#!/usr/bin/env bash
#
# Tests for scripts/guard-simulator.py: feeds it tool calls as JSON on stdin and
# checks the exit code (2 = blocked, 0 = allowed). Needs the pinned simulators
# from sim-config.sh to exist; boots nothing.
#
# Usage: ./scripts/test-guard-simulator.sh

set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/sim-config.sh

UDID=$(sim_udid) || exit 1
IPAD=$(ipad_udid) || exit 1
OTHER="00000000-0000-0000-0000-000000000000"
failures=0

check() {
  local expected="$1" command="$2" actual
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$command" \
    | scripts/guard-simulator.py 2>/dev/null
  actual=$?
  if [ "$actual" = "$expected" ]; then
    printf 'ok    %s  %s\n' "$expected" "$(printf '%s' "$command" | head -1)"
  else
    printf 'FAIL  expected %s, got %s: %s\n' "$expected" "$actual" "$command"
    failures=$((failures + 1))
  fi
}

# Blocked.
check 2 "xcodebuild -project DepthWeaver.xcodeproj -scheme DepthWeaver build"
check 2 "xcrun xcodebuild -scheme DepthWeaver test"
check 2 "xcodebuild -scheme DepthWeaver -destination 'generic/platform=iOS Simulator' build"
check 2 "xcodebuild -scheme DepthWeaver -destination 'platform=iOS Simulator,id=${OTHER}' build"
check 2 "xcodebuild -scheme DepthWeaver -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' build"
check 2 "cd /tmp && DEVELOPER_DIR=/x xcodebuild -scheme DepthWeaver build"
check 2 "xcrun simctl boot booted"
check 2 "xcrun simctl boot ${OTHER}"
check 2 "xcrun simctl install booted build/DepthWeaver.app"
check 2 "xcrun simctl io booted screenshot shot.png"
check 2 "./scripts/xcb.sh build && xcrun simctl boot ${OTHER}"

# Allowed.
check 0 "./scripts/xcb.sh build"
check 0 "./scripts/xcb.sh test -only-testing:DepthWeaverTests"
check 0 "xcodebuild -scheme DepthWeaver -destination generic/platform=iOS -archivePath build/a.xcarchive archive"
check 0 "xcodebuild -scheme DepthWeaver -destination generic/platform=macOS archive"
check 0 "xcodebuild -exportArchive -archivePath build/a.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export-ios"
check 0 "xcodebuild -scheme DepthWeaver -destination 'platform=macOS,arch=arm64' build"
check 0 "xcodebuild -scheme DepthWeaver -destination 'platform=iOS Simulator,id=${UDID}' build"
check 0 "xcodebuild -scheme DepthWeaver -destination 'platform=iOS Simulator,id=${IPAD}' build"
check 0 "xcodebuild -list -project DepthWeaver.xcodeproj"
check 0 "xcodebuild -project DepthWeaver.xcodeproj -showBuildSettings"
check 0 "xcrun simctl boot ${UDID}"
check 0 "xcrun simctl boot ${IPAD}"
check 0 "xcrun simctl shutdown ${OTHER}"
check 0 "xcrun simctl list devices booted"
check 0 "echo 'xcodebuild build'"
check 0 "grep -n xcodebuild CLAUDE.md"
check 0 "cat > notes.md <<'EOF'
Run xcodebuild -scheme DepthWeaver build, never simctl boot booted.
EOF"
check 0 "cat <<EOF | tee x.txt
echo 'xcodebuild'
xcrun simctl boot booted
EOF"

# Unreadable input never blocks the session.
if echo 'not json' | scripts/guard-simulator.py 2>/dev/null; then
  echo "ok    0  (invalid JSON on stdin)"
else
  echo "FAIL  invalid JSON on stdin was blocked"; failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "${failures} failure(s)"
  exit 1
fi
echo "all passed"
