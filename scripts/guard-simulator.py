#!/usr/bin/env python3
"""PreToolUse hook: refuse a Bash command that would drive another simulator.

This Mac has limited resources and cannot afford several booted simulators.
The convention is written in `CLAUDE.md`, but a convention is only a request —
this is what makes it hold. Reads the tool call as JSON on stdin; exit 2 blocks
the call and hands stderr back to the agent, exit 0 lets it through.

The device is never defined here: it comes from `scripts/sim-config.sh`, so the
guard and the scripts cannot drift apart. The App Store screenshots iPad
(`IPAD_DEVICE` there) is allowed too; everything else is refused.

What passes:
  - `./scripts/xcb.sh …` (its xcodebuild calls are already pinned);
  - xcodebuild archive / -exportArchive and read-only queries (-list,
    -showBuildSettings, -showdestinations, -version, …);
  - device and Mac destinations: generic/platform=iOS, generic/platform=macOS,
    platform=macOS;
  - an iOS Simulator destination naming the pinned iPhone or the iPad;
  - simctl calls on the pinned iPhone or the iPad by UDID, and `simctl list`.
What is refused:
  - xcodebuild without -destination (Xcode picks a device by itself);
  - generic/platform=iOS Simulator;
  - an iOS Simulator destination naming any other device;
  - `simctl … booted` (hits whichever simulator happens to be up), and
    `simctl boot|bootstatus` on any other device.

Wired from `.claude/settings.json` as a `PreToolUse` hook on `Bash`.
Test it by piping a tool call in:
  echo '{"tool_input":{"command":"xcodebuild build"}}' | scripts/guard-simulator.py
"""

import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SEPARATORS = re.compile(r"(?:&&|\|\||[;&|\n(){}]|`|\$\()")
HEREDOC = re.compile(r"<<-?\s*[\"']?(\w+)[\"']?")
ASSIGNMENT = re.compile(r"^\w+=")
PREFIXES = ("xcrun", "env", "time", "command", "exec", "nohup")
# Calls that never boot a simulator.
READ_ONLY = ("archive", "-exportArchive", "-showBuildSettings", "-showdestinations",
             "-list", "-version", "-showsdks", "-help", "-usage", "-license",
             "-checkFirstLaunchStatus", "-runFirstLaunch", "-downloadPlatform")
# Destinations that are not simulators: nothing to boot.
NON_SIMULATOR = ("generic/platform=iOS", "generic/platform=macOS", "platform=macOS")


def sim_config():
    """Pinned device name and UDID, iPad name and UDID, from sim-config.sh.

    A UDID is "" when it cannot be resolved.
    """
    script = ('source "$1/scripts/sim-config.sh"; echo "$SIM_DEVICE"; '
              'echo "$(sim_udid 2>/dev/null)"; echo "$IPAD_DEVICE"; '
              'echo "$(ipad_udid 2>/dev/null)"')
    out = subprocess.run(["bash", "-c", script, "_", REPO],
                         capture_output=True, text=True)
    lines = out.stdout.splitlines() + ["", "", "", ""]
    return tuple(lines[:4])


def strip_heredocs(text):
    """Drop heredoc bodies: they are data, not commands.

    Writing *about* xcodebuild — in a markdown file, a comment, this very
    script — must not trip the guard.
    """
    kept, lines, i = [], text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        match = HEREDOC.search(line)
        if match:
            tag = match.group(1)
            i += 1
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
        i += 1
    return "\n".join(kept)


def invocations(text, name):
    """Command segments whose first word is `name`, after env/xcrun prefixes."""
    for segment in SEPARATORS.split(text):
        words = segment.split()
        while words and (words[0] in PREFIXES or ASSIGNMENT.match(words[0])):
            words = words[1:]
        if words and words[0].strip("'\"").rsplit("/", 1)[-1] == name:
            yield " ".join(words)


def refuse(device, why):
    print(f"Blocked: this repository uses one simulator only — {device}.", file=sys.stderr)
    print(f"\n{why}\n", file=sys.stderr)
    print("Go through the wrapper, which pins the destination and DerivedData:",
          file=sys.stderr)
    print("  ./scripts/xcb.sh build | run | test | test-mac | mac | strings | gen",
          file=sys.stderr)
    print("  ./scripts/xcb.sh archive-ios | archive-mac", file=sys.stderr)
    print("  ./scripts/xcb.sh -- <raw xcodebuild arguments>", file=sys.stderr)
    print("See scripts/sim-config.sh and the simulator section of CLAUDE.md.",
          file=sys.stderr)
    sys.exit(2)


def main():
    try:
        command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except Exception:
        return  # A hook that cannot read its input must not block the session.
    if not command:
        return
    # Nothing else can boot a simulator: skip the simctl round trip.
    if "xcodebuild" not in command and "simctl" not in command:
        return

    body = strip_heredocs(command)
    xcodebuild_calls = list(invocations(body, "xcodebuild"))
    simctl_calls = list(invocations(body, "simctl"))
    if not xcodebuild_calls and not simctl_calls:
        return

    device, udid, ipad, ipad_id = sim_config()
    if not device:
        return

    def pinned(segment):
        return any(token and token in segment for token in (device, udid, ipad, ipad_id))

    for call in xcodebuild_calls:
        words = call.split()
        if any(flag in words for flag in READ_ONLY):
            continue
        if "generic/platform=iOS Simulator" in call:
            refuse(device, "\"generic/platform=iOS Simulator\" leaves the device up to Xcode.")
        if "-destination" not in words and not any(w.startswith("-destination=") for w in words):
            refuse(device, "This xcodebuild call has no -destination: "
                           "Xcode picks a device by itself.")
        if "platform=iOS Simulator" in call:
            if not pinned(call):
                refuse(device, f"Its -destination names a simulator other than {device}.")
            continue
        if any(dest in call for dest in NON_SIMULATOR):
            continue

    for call in simctl_calls:
        words = [w.strip("'\"") for w in call.split()]
        verb = words[1] if len(words) > 1 else ""
        if verb == "list":
            continue
        if "booted" in words[2:]:
            refuse(device, "\"booted\" targets whichever simulator happens to be up; "
                           f"pass the UDID of {device} ({udid or 'see sim-config.sh'}).")
        if verb in ("boot", "bootstatus") and not pinned(call):
            refuse(device, f"It boots a simulator other than {device}.")


main()
