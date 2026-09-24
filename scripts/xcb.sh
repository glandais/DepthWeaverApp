#!/usr/bin/env bash
#
# The only way to run xcodebuild in this repository.
#
# It pins the iOS destination to the single simulator declared in
# `sim-config.sh` (macOS builds go to `platform=macOS,arch=arm64`), and uses a
# repo-local DerivedData, so that no build boots a device of its own choosing.
# `scripts/guard-simulator.py` enforces it for agents.
#
# Usage:
#   ./scripts/xcb.sh gen              (re)generate the .xcodeproj from project.yml
#   ./scripts/xcb.sh build            build the DepthWeaver scheme for the iOS simulator (Debug)
#   ./scripts/xcb.sh run              build, install and launch on the pinned simulator
#   ./scripts/xcb.sh test             run DepthWeaverTests on the pinned simulator
#   ./scripts/xcb.sh test-mac         run DepthWeaverTests on this Mac (arm64)
#   ./scripts/xcb.sh mac              build the DepthWeaver scheme for macOS (Debug, arm64)
#   ./scripts/xcb.sh strings          build iOS + macOS, then sync Localizable.xcstrings
#   ./scripts/xcb.sh archive-ios      Release archive + export to build/export-ios (.ipa)
#   ./scripts/xcb.sh archive-mac      strip quarantine, Release archive + export to build/export-mac (.pkg)
#   ./scripts/xcb.sh -- <args...>     raw xcodebuild, destination still pinned to the simulator
#
# Arguments after the subcommand are passed to xcodebuild.
#
# The archive commands never upload anything: they print the `asc builds upload`
# command to run next. Set DEPTHWEAVER_ALLOW_PROVISIONING_UPDATES=1 to pass
# -allowProvisioningUpdates to archive and export (lets Xcode create or refresh
# signing assets on the developer portal).

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sim-config.sh

PROJECT="DepthWeaver.xcodeproj"
SCHEME="${DEPTHWEAVER_SCHEME:-DepthWeaver}"
TEST_SCHEME="DepthWeaverTests"
BUNDLE_ID="io.github.glandais.depthweaver"
ASC_APP_ID="6764146054"
CATALOG="DepthWeaver/Resources/Localizable.xcstrings"
INFO_CATALOG="DepthWeaver/Resources/InfoPlist.xcstrings"
MAC_DEST="platform=macOS,arch=arm64"
ARCHIVE_DIR="build"

# The .xcodeproj is not versioned: in a fresh worktree, or after adding a file,
# it must be regenerated. Without it the build fails with a "cannot find X in
# scope" that has nothing to do with the code.
generate() {
  command -v xcodegen >/dev/null || {
    echo "xcb: xcodegen is missing (brew install xcodegen)" >&2
    exit 1
  }
  echo "▸ xcodegen generate"
  xcodegen generate --quiet
}

usage() {
  sed -n '/^# Usage:/,/^# Arguments after/p' "$0" | sed 's/^#\{1,\} \{0,1\}//' >&2
}

provisioning_flags=()
if [ "${DEPTHWEAVER_ALLOW_PROVISIONING_UPDATES:-0}" = "1" ]; then
  provisioning_flags=(-allowProvisioningUpdates)
fi

command="${1:-build}"
shift || true

case "$command" in
  -h|--help|help) usage; exit 0 ;;
esac

if [ "$command" = gen ]; then
  generate
  exit 0
fi

[ -d "$PROJECT" ] || generate

# iOS simulator xcodebuild, pinned.
xcb_sim() {
  local scheme="$1"; shift
  xcodebuild -project "$PROJECT" -scheme "$scheme" \
    -destination "$(sim_dest "$UDID")" -derivedDataPath "$DERIVED_DATA" "$@"
}

# macOS xcodebuild, Apple Silicon only (the app excludes x86_64: Float16).
xcb_mac() {
  local scheme="$1"; shift
  xcodebuild -project "$PROJECT" -scheme "$scheme" \
    -destination "$MAC_DEST" -derivedDataPath "$DERIVED_DATA" "$@"
}

# Release archive to $1 for destination $2, then export with plist $3 to $4.
archive_and_export() {
  local archive="$1" dest="$2" options="$3" export_path="$4"; shift 4
  [ -f "$options" ] || { echo "xcb: missing ${options}" >&2; exit 1; }
  rm -rf "$archive" "$export_path"
  echo "▸ archive (Release) → ${archive}"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination "$dest" -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$archive" ${provisioning_flags[@]+"${provisioning_flags[@]}"} \
    archive "$@"
  echo "▸ export (${options}) → ${export_path}"
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$options" -exportPath "$export_path" \
    ${provisioning_flags[@]+"${provisioning_flags[@]}"}
}

case "$command" in
  build)
    UDID=$(sim_udid)
    echo "▸ build on ${SIM_DEVICE} (${UDID})"
    xcb_sim "$SCHEME" build "$@"
    ;;

  run)
    UDID=$(sim_udid)
    # Explicit path to the Debug product: a stale Release-iphonesimulator/ can
    # sit in the same folder, and a `find … | head -1` would pick it up and
    # install a binary from before the change.
    echo "▸ build on ${SIM_DEVICE} (${UDID})"
    xcb_sim "$SCHEME" build "$@"
    app="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/DepthWeaver.app"
    [ -d "$app" ] || { echo "xcb: product not found: ${app}" >&2; exit 1; }
    sim_boot "$UDID"
    echo "▸ install ${app}"
    xcrun simctl install "$UDID" "$app"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    ;;

  test)
    UDID=$(sim_udid)
    # Boot explicitly (shutting down any other simulator) rather than letting
    # xcodebuild do it, so the one-simulator rule holds.
    sim_boot "$UDID"
    echo "▸ test ${TEST_SCHEME} on ${SIM_DEVICE} (${UDID})"
    xcb_sim "$TEST_SCHEME" test "$@"
    ;;

  test-mac)
    echo "▸ test ${TEST_SCHEME} on ${MAC_DEST}"
    xcb_mac "$TEST_SCHEME" test "$@"
    ;;

  mac)
    echo "▸ build on ${MAC_DEST}"
    xcb_mac "$SCHEME" build "$@"
    ;;

  strings)
    # `xcstringstool sync` has several silent ways of wrecking the catalog, all
    # handled here:
    #  - the catalog is synced in place: a copy outside the repo resolves no
    #    source and marks every key stale;
    #  - *every* architecture slice is passed, not just the first one a
    #    `head -1` would keep: leaving one out erases the extractionState of
    #    the others;
    #  - *both* platforms are built and passed: macOS-only code (menus,
    #    toolbar, inspector) is in no iOS slice, and an iOS-only sync marks
    #    its keys stale (and the other way round for iOS-only screens);
    #  - the compiler extracts nothing from an NSLocalizedString whose
    #    `bundle:` is a variable (the Object Capture strings ported from
    #    Apple's sample), and sync deletes such a key outright when it has no
    #    translation yet. Every key the sync drops whose literal still appears
    #    in a Swift source is put back, unchanged.
    # InfoPlist.xcstrings is NOT synced: its keys come from INFOPLIST_KEY_*
    # build settings, not from Swift, so a sync against these stringsdata marks
    # every one of them stale and drops the untranslated ones. Edit it through
    # i18n/translations.json.
    UDID=$(sim_udid)
    echo "▸ build on ${SIM_DEVICE} (${UDID})"
    xcb_sim "$SCHEME" build "$@" >/dev/null
    echo "▸ build on ${MAC_DEST}"
    xcb_mac "$SCHEME" build "$@" >/dev/null
    intermediates="${DERIVED_DATA}/Build/Intermediates.noindex/DepthWeaver.build"
    shopt -s nullglob
    ios_slices=("$intermediates"/Debug-iphonesimulator/DepthWeaver.build/Objects-normal/*/*.stringsdata)
    mac_slices=("$intermediates"/Debug/DepthWeaver.build/Objects-normal/*/*.stringsdata)
    shopt -u nullglob
    if [ "${#ios_slices[@]}" -eq 0 ] || [ "${#mac_slices[@]}" -eq 0 ]; then
      echo "xcb: no .stringsdata for iOS (${#ios_slices[@]}) or macOS (${#mac_slices[@]}) under ${intermediates} (is SWIFT_EMIT_LOC_STRINGS on?)" >&2
      exit 1
    fi
    before=$(mktemp)
    trap 'rm -f "$before"' EXIT
    cp "$CATALOG" "$before"
    echo "▸ syncing ${CATALOG} from ${#ios_slices[@]} iOS + ${#mac_slices[@]} macOS stringsdata file(s)"
    xcrun xcstringstool sync "$CATALOG" --stringsdata "${ios_slices[@]}" "${mac_slices[@]}"
    python3 - "$before" "$CATALOG" <<'PY'
import json, re, sys
from pathlib import Path
sys.path.insert(0, "scripts")
from i18n import catalog_style, dump_catalog

before = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["strings"]
path = Path(sys.argv[2])
data = json.loads(path.read_text(encoding="utf-8"))
source = "\n".join(p.read_text(encoding="utf-8") for p in Path("DepthWeaver").rglob("*.swift"))
# Multi-line """ literals, with their indentation stripped as Swift does.
multiline = {"\n".join(line.strip() for line in m.split("\n"))
             for m in re.findall(r'"""\n(.*?)\n\s*"""', source, re.DOTALL)}

def used(key):
    return json.dumps(key, ensure_ascii=False) in source or key in multiline

dropped = [k for k in before if k not in data["strings"]]
kept = [k for k in dropped if used(k)]
if kept:
    style = catalog_style(path)
    data["strings"].update({k: before[k] for k in kept})
    data["strings"] = dict(sorted(data["strings"].items()))  # sync writes them sorted
    path.write_text(dump_catalog(data, style), encoding="utf-8")
print(f"▸ {len(kept)} key(s) the sync dropped but the code still uses were put back;"
      f" {len(dropped) - len(kept)} key(s) no longer in the code were removed")
PY
    echo "▸ done. Run ./scripts/i18n.py export, then fill in every locale of each"
    echo "  new key; extractionState: stale marks a dead key."
    ;;

  archive-ios)
    archive_and_export "${ARCHIVE_DIR}/DepthWeaver-iOS.xcarchive" "generic/platform=iOS" \
      ExportOptions.plist "${ARCHIVE_DIR}/export-ios" "$@"
    ipa=$(ls "${ARCHIVE_DIR}"/export-ios/*.ipa 2>/dev/null | head -1 || true)
    [ -n "$ipa" ] || { echo "xcb: no .ipa in ${ARCHIVE_DIR}/export-ios" >&2; exit 1; }
    echo "▸ exported ${ipa}. Nothing was uploaded. To upload:"
    echo "  asc builds upload --app ${ASC_APP_ID} --ipa \"${ipa}\" --wait"
    ;;

  archive-mac)
    # Apple rejects distributed macOS apps whose bundle carries
    # com.apple.quarantine (ITMS-91109); some resources were downloaded from
    # the web and keep it. Strip it from the sources, then prove none is left.
    echo "▸ stripping com.apple.quarantine from DepthWeaver/"
    xattr -rd com.apple.quarantine DepthWeaver 2>/dev/null || true
    left=$(xattr -lr DepthWeaver 2>/dev/null | grep -c 'com.apple.quarantine' || true)
    if [ "${left:-0}" != "0" ]; then
      echo "xcb: ${left} file(s) under DepthWeaver/ still carry com.apple.quarantine:" >&2
      xattr -lr DepthWeaver | grep 'com.apple.quarantine' >&2
      exit 1
    fi
    archive_and_export "${ARCHIVE_DIR}/DepthWeaver-macOS.xcarchive" "generic/platform=macOS" \
      ExportOptions-macOS.plist "${ARCHIVE_DIR}/export-mac" "$@"
    pkg=$(ls "${ARCHIVE_DIR}"/export-mac/*.pkg 2>/dev/null | head -1 || true)
    [ -n "$pkg" ] || { echo "xcb: no .pkg in ${ARCHIVE_DIR}/export-mac" >&2; exit 1; }
    # A .pkg upload needs the version and build number spelled out (an .ipa
    # carries them): read them from the archived app.
    app_plist="${ARCHIVE_DIR}/DepthWeaver-macOS.xcarchive/Products/Applications/DepthWeaver.app/Contents/Info.plist"
    mac_version=$(plutil -extract CFBundleShortVersionString raw "$app_plist")
    mac_build=$(plutil -extract CFBundleVersion raw "$app_plist")
    echo "▸ exported ${pkg}. Nothing was uploaded. To upload:"
    echo "  asc builds upload --app ${ASC_APP_ID} --pkg \"${pkg}\" --version ${mac_version} --build-number ${mac_build} --wait"
    ;;

  --)
    UDID=$(sim_udid)
    xcb_sim "$SCHEME" "$@"
    ;;

  *)
    echo "xcb: unknown subcommand \"${command}\"" >&2
    usage
    exit 1
    ;;
esac
