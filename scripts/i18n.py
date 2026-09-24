#!/usr/bin/env python3
"""Gather every translation of the repository into one JSON file, and put it back.

    ./scripts/i18n.py export [-o i18n/translations.json]   # sources -> one JSON
    ./scripts/i18n.py import [-i i18n/translations.json]   # one JSON -> sources
    ./scripts/i18n.py check                                # the round trip is byte-exact

What it covers, in English and French:

  * `DepthWeaver/Resources/Localizable.xcstrings`   - the screens
  * `DepthWeaver/Resources/InfoPlist.xcstrings`     - display name, permission prompts
  * `screenshots/koubou/koubou-strings.xcstrings`   - the App Store card headlines
  * `metadata/app-info/<locale>.json`               - store name, subtitle, privacy URL
  * `metadata/version/<latest>/<locale>.json`       - description, keywords, what's new

The mapping is a bijection: an `import` run right after an `export` rewrites each
of these files byte for byte, so the JSON can be edited (or handed to a
translator) and put back without losing plural variations, substitutions,
comments, extraction states, `shouldTranslate`, key order or file formatting.

Only the **latest** version directory under `metadata/version/` is covered. The
older ones (1.0, 1.1.0) are versions App Store Connect has already released: their
description and keywords can no longer be changed there, so offering them for
translation would only invite edits that go nowhere. They stay on disk as
history, untouched by `import`.

DepthWeaver's catalog mixes two kinds of keys: dotted names (`about.more_apps`)
and the English sentence itself (`Choose a pattern`), which is how SwiftUI
extracts a `Text("...")`. Both are legitimate here; the export does not judge
them. It reports instead what still needs work:

  * `missingFrench` - live keys (not `stale`, not `shouldTranslate: false`) with
    no `fr` unit: the French app shows the English key or value for them;
  * `needsReview`   - units whose state is not `translated` (`new`,
    `needs_review`): Xcode wrote them, nobody has confirmed them;
  * `stale`         - keys `xcstringstool` no longer finds in the code.

The Koubou catalog's keys are the English sentence: that is how Koubou finds the
translation of a variable of `screenshots/koubou/*.yaml`. `check` verifies that
every variable of every configuration is a key of that catalog, and that
configurations with the same cards (iPhone and iPad) say the same thing.

Deliberately out of scope, because they are English by nature or carry no
prose: `metadata/review-notes.md` and `metadata/app-privacy.json`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "DepthWeaver" / "Resources"

CATALOGS = {
    "Localizable": RESOURCES / "Localizable.xcstrings",
    "InfoPlist": RESOURCES / "InfoPlist.xcstrings",
    "Koubou": ROOT / "screenshots" / "koubou" / "koubou-strings.xcstrings",
}
KOUBOU_DIR = ROOT / "screenshots" / "koubou"
# Koubou variables that steer the layout instead of carrying text: their value is
# a template keyword (`left`, `center`). Koubou looks every variable up in the
# catalog all the same, so those keywords are catalog keys too (with an empty
# `needs_translation` French unit, which Koubou reads as "keep the English");
# they are left out of the to-do reports and of the iPhone/iPad comparison.
KOUBOU_LAYOUT_VARIABLES = {"align"}
METADATA = ROOT / "metadata"
DEFAULT_JSON = ROOT / "i18n" / "translations.json"

# The app catalogs use short language codes; App Store Connect has its own for
# the same languages, and those name the files under `metadata/` (and the
# locales of the Koubou catalog).
LOCALE_MAP = {"en": "en-US", "fr": "fr-FR"}
FRENCH = {"fr", "fr-FR"}

UNIT_KEYS = ("stringUnit", "variations", "substitutions")

# ---------------------------------------------------------------- catalog i/o

def catalog_style(path: Path) -> tuple[str, str]:
    """Sniff how this catalog is already written, so a rewrite changes nothing.

    Xcode writes `"key" : value`; a file written by another tool (Koubou's
    catalog) may use the compact `"key": value`. Keep the one on disk, and its
    final newline (or its absence: Xcode writes none)."""
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    colon = " : " if '" : ' in text else ": "
    return colon, "\n" if text.endswith("\n") else ""


# Xcode writes an empty object on three lines - `{`, a blank line, `}` - where
# `json.dumps` writes `{}`. Harmless today (no entry is empty), but the first key
# `xcstringstool` extracts with neither comment nor value would break the round
# trip without it.
EMPTY_OBJECT = re.compile(r"^(\s*)(.*): \{\}(,?)$", re.MULTILINE)


def sorted_tree(node: object) -> object:
    if isinstance(node, dict):
        return {k: sorted_tree(node[k]) for k in sorted(node)}
    if isinstance(node, list):
        return [sorted_tree(v) for v in node]
    return node


def dump_catalog(data: dict, style: tuple[str, str]) -> str:
    """Every object is written with sorted keys, as Xcode does, except the
    `strings` table itself: its order is kept as it came. `xcstringstool sync`
    (`xcb.sh strings`) writes it sorted, but a catalog edited in Xcode may have
    keys appended out of order; re-sorting it here would rewrite the whole
    file behind the user's back."""
    colon, tail = style
    ordered = {k: sorted_tree(v) for k, v in sorted(data.items()) if k != "strings"}
    ordered["strings"] = {k: sorted_tree(v) for k, v in data["strings"].items()}
    ordered = {k: ordered[k] for k in sorted(ordered)}
    text = json.dumps(ordered, indent=2, ensure_ascii=False, separators=(",", colon))
    text = EMPTY_OBJECT.sub(lambda m: f"{m[1]}{m[2]}: {{\n\n{m[1]}}}{m[3]}", text)
    return text + tail

# ------------------------------------------------------- unit encode / decode
# A "unit node" is anything that carries stringUnit / variations / substitutions:
# a localization, a variation case, or the body of a substitution.

def encode_unit(node: dict, where: str) -> object:
    unknown = set(node) - set(UNIT_KEYS)
    if unknown:
        # Fail loudly rather than drop a field the round trip would lose.
        raise SystemExit(f"i18n: {where}: unknown localization field(s) {sorted(unknown)}")
    out: dict = {}
    unit = node.get("stringUnit")
    if unit is not None:
        if set(unit) - {"state", "value"}:
            raise SystemExit(f"i18n: {where}: unknown stringUnit field(s) "
                             f"{sorted(set(unit) - {'state', 'value'})}")
        out["value"] = unit["value"]
        if unit.get("state") != "translated":
            out["state"] = unit.get("state")
    if "variations" in node:
        out["variations"] = {
            kind: {case: encode_unit(body, f"{where}/{kind}/{case}")
                   for case, body in cases.items()}
            for kind, cases in node["variations"].items()
        }
    if "substitutions" in node:
        subs = {}
        for name, sub in node["substitutions"].items():
            body = encode_unit({k: v for k, v in sub.items() if k in UNIT_KEYS},
                               f"{where}/{name}")
            if not isinstance(body, dict):
                body = {"value": body}
            entry = {k: v for k, v in sub.items() if k not in UNIT_KEYS}
            entry.update(body)
            subs[name] = entry
        out["substitutions"] = subs
    # the common case - a plain translated string - stays a bare string
    if list(out) == ["value"]:
        return out["value"]
    return out


def decode_unit(node: object) -> dict:
    if isinstance(node, str):
        return {"stringUnit": {"state": "translated", "value": node}}
    out: dict = {}
    if "value" in node:
        out["stringUnit"] = {"state": node.get("state", "translated"),
                             "value": node["value"]}
    if "variations" in node:
        out["variations"] = {
            kind: {case: decode_unit(body) for case, body in cases.items()}
            for kind, cases in node["variations"].items()
        }
    if "substitutions" in node:
        subs = {}
        for name, entry in node["substitutions"].items():
            body = decode_unit({k: v for k, v in entry.items()
                                if k in ("value", "state", "variations", "substitutions")})
            meta = {k: v for k, v in entry.items()
                    if k not in ("value", "state", "variations", "substitutions")}
            subs[name] = {**meta, **body}
        out["substitutions"] = subs
    return out


def encode_catalog(path: Path) -> dict:
    cat = json.loads(path.read_text(encoding="utf-8"))
    keys = {}
    for key, entry in cat["strings"].items():
        # Every entry field other than the localizations (comment,
        # extractionState, isCommentAutoGenerated, shouldTranslate...) is
        # carried over as is.
        out = {k: v for k, v in entry.items() if k != "localizations"}
        if "translations" in out:
            raise SystemExit(f"i18n: {path.name}: key {key!r} has a 'translations' field")
        out["translations"] = {lang: encode_unit(loc, f"{path.name}:{key}/{lang}")
                               for lang, loc in entry.get("localizations", {}).items()}
        keys[key] = out
    header = {k: v for k, v in cat.items() if k != "strings"}
    return {"path": str(path.relative_to(ROOT)), **header, "keys": keys}


def decode_catalog(table: dict) -> dict:
    strings = {}
    for key, entry in table["keys"].items():
        out = {k: v for k, v in entry.items() if k != "translations"}
        # A key without any localization is written by `xcstringstool` with no
        # `localizations` field at all: adding an empty one would make the
        # round trip diverge on every sync.
        if entry["translations"]:
            out["localizations"] = {lang: decode_unit(node)
                                    for lang, node in entry["translations"].items()}
        strings[key] = out
    header = {k: v for k, v in table.items() if k not in ("path", "keys")}
    return {**header, "strings": strings}

# ------------------------------------------------------------------- metadata

def version_key(name: str) -> tuple:
    return tuple(int(p) if p.isdigit() else -1 for p in name.split("."))


def latest_version_dir() -> Path | None:
    dirs = [d for d in (METADATA / "version").iterdir()
            if d.is_dir() and re.fullmatch(r"\d+(\.\d+)*", d.name)]
    return max(dirs, key=lambda d: version_key(d.name)) if dirs else None


def metadata_files() -> list[Path]:
    files = sorted((METADATA / "app-info").glob("*.json"))
    latest = latest_version_dir()
    if latest is not None:
        files += sorted(latest.glob("*.json"))
    return files


def encode_metadata() -> dict:
    """One entry per canonical metadata file, key order included."""
    scopes: dict = {}
    for path in metadata_files():
        rel = path.relative_to(METADATA)
        scope = "app-info" if rel.parts[0] == "app-info" else f"version/{rel.parts[1]}"
        scopes.setdefault(scope, {})[path.stem] = json.loads(
            path.read_text(encoding="utf-8"))
    return {"path": str(METADATA.relative_to(ROOT)), "scopes": scopes}


def metadata_style(path: Path) -> dict:
    """Sniff how a metadata file is written: `asc metadata pull` writes
    indented JSON with a final newline, but files edited by hand over the
    versions came out compact, with or without spaces and newline. A rewrite
    keeps whichever the file on disk uses; a new file gets the indented form."""
    default = {"indent": 2, "separators": (",", ": "), "tail": "\n", "ascii": False}
    if not path.exists():
        return default
    text = path.read_text(encoding="utf-8")
    tail = "\n" if text.endswith("\n") else ""
    ascii_only = "\\u" in text and text.isascii()
    if text.startswith("{\n"):
        return {**default, "tail": tail, "ascii": ascii_only}
    m = re.match(r'\{("(?:[^"\\]|\\.)*")(\s*:\s*)', text)
    if not m:
        return {**default, "tail": tail, "ascii": ascii_only}
    _, end = json.JSONDecoder().raw_decode(text, m.end())
    item = re.match(r"\s*,\s*", text[end:])
    return {"indent": None,
            "separators": (item[0] if item else ", ", m[2]),
            "tail": tail, "ascii": ascii_only}


def dump_metadata_file(payload: dict, style: dict) -> str:
    return json.dumps(payload, indent=style["indent"], separators=style["separators"],
                      ensure_ascii=style["ascii"]) + style["tail"]


def metadata_targets(meta: dict) -> list[tuple[Path, str]]:
    out = []
    for scope, locales in meta["scopes"].items():
        for locale, payload in locales.items():
            path = METADATA / scope / f"{locale}.json"
            out.append((path, dump_metadata_file(payload, metadata_style(path))))
    return out

# ------------------------------------------------------------------- reports

def unit_states(node: object) -> set:
    """Every stringUnit state found in an encoded unit, variations included."""
    if isinstance(node, str):
        return {"translated"}
    states = set()
    if "value" in node:
        states.add(node.get("state", "translated"))
    for cases in node.get("variations", {}).values():
        for body in cases.values():
            states |= unit_states(body)
    for sub in node.get("substitutions", {}).values():
        states |= unit_states(sub)
    return states


def build_reports(tables: dict) -> dict:
    missing, review, stale = {}, {}, {}
    layout = koubou_layout_values()
    for name, table in tables.items():
        miss, rev, dead = [], [], []
        for key, entry in table["keys"].items():
            if name == "Koubou" and key in layout:
                continue
            if entry.get("extractionState") == "stale":
                dead.append(key)
                continue
            if entry.get("shouldTranslate") is False:
                continue
            if not FRENCH & set(entry["translations"]):
                miss.append(key)
            for lang, node in entry["translations"].items():
                if unit_states(node) - {"translated"}:
                    rev.append(f"{key} [{lang}]")
        if miss:
            missing[name] = sorted(miss)
        if rev:
            review[name] = sorted(rev)
        if dead:
            stale[name] = sorted(dead)
    return {"missingFrench": missing, "needsReview": review, "stale": stale}

# ------------------------------------------------------------------ commands

def build_export() -> dict:
    tables = {name: encode_catalog(path) for name, path in CATALOGS.items()}
    return {
        "generatedBy": "scripts/i18n.py export",
        "languages": {"catalog": sorted(LOCALE_MAP),
                      "appStoreConnect": sorted(LOCALE_MAP.values())},
        "localeMap": LOCALE_MAP,
        **build_reports(tables),
        "tables": tables,
        "metadata": encode_metadata(),
    }


def count(report: dict) -> int:
    return sum(len(v) for v in report.values())


def cmd_export(args) -> int:
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    data = build_export()
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    keys = sum(len(t["keys"]) for t in data["tables"].values())
    units = sum(len(k["translations"])
                for t in data["tables"].values() for k in t["keys"].values())
    fields = sum(len(p) for s in data["metadata"]["scopes"].values()
                 for p in s.values())
    shown = out.relative_to(ROOT) if out.is_relative_to(ROOT) else out
    print(f"{shown}: {keys} keys, {units} localizations, "
          f"{fields} metadata fields ({', '.join(data['metadata']['scopes'])})")
    print(f"  {count(data['missingFrench'])} live keys without French, "
          f"{count(data['needsReview'])} units not 'translated', "
          f"{count(data['stale'])} stale keys")
    return 0


def cmd_import(args) -> int:
    data = json.loads(Path(args.input).read_text(encoding="utf-8"))
    for table in data["tables"].values():
        path = ROOT / table["path"]
        path.write_text(dump_catalog(decode_catalog(table), catalog_style(path)),
                        encoding="utf-8")
        print(f"wrote {table['path']} ({len(table['keys'])} keys)")
    targets = metadata_targets(data["metadata"])
    for path, body in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
    print(f"wrote {len(targets)} files under {data['metadata']['path']}/ "
          f"({', '.join(data['metadata']['scopes'])})")
    return 0


def koubou_configs() -> list[Path]:
    return sorted(p for p in KOUBOU_DIR.glob("[!.]*.yaml")
                  if not p.name.endswith(".local.yaml"))


def koubou_variables(path: Path) -> dict:
    import yaml
    config = yaml.safe_load(path.read_text(encoding="utf-8"))
    return {card: dict(spec.get("variables") or {})
            for card, spec in (config.get("screenshots") or {}).items()}


def koubou_layout_values() -> set:
    return {value for p in koubou_configs() for card in koubou_variables(p).values()
            for var, value in card.items() if var in KOUBOU_LAYOUT_VARIABLES}


def check_koubou(keys: set) -> bool:
    """Every variable is a catalog key, and configurations with the same cards
    (iPhone, iPad) say the same thing. The Mac has its own cards."""
    ok = True
    seen = {p.name: koubou_variables(p) for p in koubou_configs()}
    used = set()
    for name, cards in seen.items():
        for card, variables in cards.items():
            for var, value in variables.items():
                used.add(value)
                if value not in keys:
                    ok = False
                    print(f"{name}: {card}.{var} is not a key of the Koubou catalog: "
                          f"{value!r}", file=sys.stderr)
    by_cards: dict = {}
    for name, cards in seen.items():
        by_cards.setdefault(tuple(sorted(cards)), []).append(name)
    def text(name: str) -> str:
        return json.dumps({card: {k: v for k, v in variables.items()
                                  if k not in KOUBOU_LAYOUT_VARIABLES}
                           for card, variables in seen[name].items()}, sort_keys=True)
    for names in by_cards.values():
        if len({text(n) for n in names}) > 1:
            ok = False
            print(f"{', '.join(names)}: same cards, different text - a headline "
                  f"changes in every configuration", file=sys.stderr)
    for orphan in sorted(keys - used):
        print(f"warning: Koubou catalog key used by no configuration: {orphan!r}",
              file=sys.stderr)
    if ok and seen:
        print(f"screenshots/koubou/: {len(seen)} configurations, "
              f"every variable is in the catalog")
    return ok


def cmd_check(args) -> int:
    data = build_export()
    ok = check_koubou(set(data["tables"]["Koubou"]["keys"]))
    for table in data["tables"].values():
        path = ROOT / table["path"]
        after = dump_catalog(decode_catalog(table), catalog_style(path))
        if path.read_text(encoding="utf-8") == after:
            print(f"{table['path']}: byte-exact round trip")
        else:
            ok = False
            print(f"{table['path']}: DIVERGES", file=sys.stderr)
    targets = metadata_targets(data["metadata"])
    bad = [p for p, text in targets if p.read_text(encoding="utf-8") != text]
    for p in bad:
        ok = False
        print(f"{p.relative_to(ROOT)}: DIVERGES", file=sys.stderr)
    if not bad:
        print(f"metadata/: byte-exact round trip ({len(targets)} files)")
    # The committed JSON must be what an export would write now: otherwise an
    # edit went to a generated file (lost at the next import), or the JSON was
    # edited and not imported.
    if DEFAULT_JSON.exists():
        current = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        if DEFAULT_JSON.read_text(encoding="utf-8") == current:
            print(f"{DEFAULT_JSON.relative_to(ROOT)}: in sync with the sources")
        else:
            ok = False
            print(f"{DEFAULT_JSON.relative_to(ROOT)}: OUT OF SYNC with the sources - "
                  f"run `import` if you edited the JSON, `export` if you edited "
                  f"a source", file=sys.stderr)
    print(f"to do: {count(data['missingFrench'])} live keys without French, "
          f"{count(data['needsReview'])} units not 'translated' "
          f"(see missingFrench / needsReview in the JSON)")
    return 0 if ok else 1


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export", help="sources -> JSON")
    e.add_argument("-o", "--output", default=str(DEFAULT_JSON))
    e.set_defaults(func=cmd_export)
    i = sub.add_parser("import", help="JSON -> sources")
    i.add_argument("-i", "--input", default=str(DEFAULT_JSON))
    i.set_defaults(func=cmd_import)
    c = sub.add_parser("check", help="byte-exact round trip, Koubou variables, JSON in sync")
    c.set_defaults(func=cmd_check)
    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
