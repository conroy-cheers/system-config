#!/usr/bin/env python3
"""Build a reproducible option catalog from a pinned QMK checkout."""

import argparse
import json
import re
from pathlib import Path

import hjson


NAME = r"[A-Z][A-Z0-9_]*"
DEFINE = re.compile(rf"#\s*define\s+({NAME})(?:\s+([^/\n]+?))?\s*(?://.*)?$")
RULE = re.compile(rf"^\s*({NAME})\s*[?:+]?=\s*(yes|no)\b", re.MULTILINE)
GUARDED_DEFAULT = re.compile(
    rf"#\s*(?:ifndef\s+({NAME})|if\s+!defined\(\s*({NAME})\s*\)[^\n]*)"
    rf"(?:(?!#\s*endif).)*?#\s*define\s+({NAME})(?:\s+([^\n/]+))?",
    re.DOTALL,
)


def load_hjson(path):
    with path.open() as handle:
        return hjson.load(handle)


def scalar_type(value):
    if value is None or not value.strip():
        return "flag"
    value = value.strip()
    if re.fullmatch(r"[-+]?\d+|0[xX][0-9a-fA-F]+", value):
        return "int"
    if value.startswith('"'):
        return "str"
    if re.fullmatch(NAME, value):
        return "symbol"
    return "raw"


def docs_options(root):
    options = {}
    for path in sorted((root / "docs").rglob("*.md")):
        heading = path.stem.replace("_", " ").title()
        lines = path.read_text(errors="replace").splitlines()
        for index, line in enumerate(lines):
            if match := re.match(r"^#{1,6}\s+(.+)$", line):
                heading = re.sub(r"[`*_]", "", match.group(1)).strip() or heading
            for match in DEFINE.finditer(line):
                name, example = match.groups()
                example = example.strip().strip("`") if example else None
                description = ""
                for following in lines[index + 1 : index + 5]:
                    text = following.strip().lstrip("*- ")
                    if text and not text.startswith(("```", "#", "<")):
                        description = re.sub(r"[`*_]", "", text)
                        break
                options.setdefault(
                    name,
                    {
                        "kind": "define",
                        "category": heading,
                        "description": description,
                        "documentation": f"{path.relative_to(root)}:{index + 1}",
                        "example": example,
                    },
                )
            for name, example in RULE.findall(line):
                options.setdefault(
                    name,
                    {
                        "kind": "rule",
                        "category": heading,
                        "description": "",
                        "documentation": f"{path.relative_to(root)}:{index + 1}",
                        "example": example,
                    },
                )
    return options


def source_options(root):
    defaults = {}
    seen = set()
    rules = set()
    roots = [root / name for name in ("quantum", "platforms", "tmk_core", "drivers", "builddefs")]
    for base in roots:
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in {".h", ".c", ".mk"} or not path.is_file():
                continue
            text = path.read_text(errors="replace")
            if path.suffix == ".mk":
                rules.update(name for name, _ in RULE.findall(text))
                rules.update(re.findall(rf"\$\(\s*({NAME})\s*\)", text))
                rules.update(re.findall(rf"\b({NAME}_ENABLE)\b", text))
            seen.update(re.findall(rf"(?:defined\s*\(\s*|#\s*ifdef\s+|#\s*ifndef\s+)({NAME})", text))
            for match in GUARDED_DEFAULT.finditer(text):
                guard = match.group(1) or match.group(2)
                defined, value = match.group(3), match.group(4)
                if guard == defined:
                    defaults.setdefault(
                        defined,
                        {
                            "default": value.strip() if value else True,
                            "source": str(path.relative_to(root)),
                        },
                    )
                    seen.add(defined)
    return seen, defaults, rules


def deep_merge(target, incoming):
    for key, value in incoming.items():
        if value == "!delete!":
            target.pop(key, None)
        elif isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value


def load_keycodes(root):
    keycode_root = root / "data/constants/keycodes"
    versions = sorted(
        {
            match.group(1)
            for path in keycode_root.glob("keycodes_*.hjson")
            if (match := re.search(r"keycodes_(\d+\.\d+\.\d+)(?:_|$)", path.stem))
        },
        key=lambda version: tuple(map(int, version.split("."))),
    )
    spec = {}
    for version in versions:
        for path in sorted(keycode_root.glob(f"keycodes_{version}*.hjson")):
            deep_merge(spec, load_hjson(path))

    values = {}
    for encoded, metadata in spec.get("keycodes", {}).items():
        if not isinstance(metadata, dict):
            continue
        value = int(encoded, 16)
        for name in [metadata.get("key"), *metadata.get("aliases", [])]:
            if name and name != "!reset!":
                values[name] = value

    # QMK's US aliases describe shifted keycodes as expressions. They are
    # data-driven too, so resolve the simple modifier expressions needed by
    # standard VIA rather than maintaining a punctuation table.
    us_files = sorted((keycode_root / "extras").glob("keycodes_us_*.hjson"))
    aliases = {}
    for path in us_files:
        deep_merge(aliases, load_hjson(path).get("aliases", {}))
    for expression, metadata in aliases.items():
        match = re.fullmatch(r"S\(([^()]+)\)", expression)
        if not match or match.group(1) not in values or not isinstance(metadata, dict):
            continue
        value = 0x0200 | values[match.group(1)]
        for name in [metadata.get("key"), *metadata.get("aliases", [])]:
            if name and name != "!reset!":
                values[name] = value
    return dict(sorted(values.items()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qmk", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--qmk-rev", required=True)
    args = parser.parse_args()

    config_mapping = load_hjson(args.qmk / "data/mappings/info_config.hjson")
    rules_mapping = load_hjson(args.qmk / "data/mappings/info_rules.hjson")
    docs = docs_options(args.qmk)
    source_seen, defaults, source_rules = source_options(args.qmk)
    keycodes = load_keycodes(args.qmk)

    entries = {}
    for name, metadata in config_mapping.items():
        if metadata.get("invalid"):
            continue
        entries[name] = {
            "kind": "define",
            "type": metadata.get("value_type", "raw"),
            "json_path": metadata.get("info_key"),
            "provenance": ["mapping"],
            "confidence": "authoritative",
        }
    for name, metadata in rules_mapping.items():
        if metadata.get("invalid"):
            continue
        entries[name] = {
            "kind": "rule",
            "type": metadata.get("value_type", "bool"),
            "json_path": metadata.get("info_key"),
            "provenance": ["mapping"],
            "confidence": "authoritative",
        }
    for name, metadata in docs.items():
        entry = entries.setdefault(
            name,
            {
                "kind": "define",
                "type": scalar_type(metadata.get("example")),
                "provenance": [],
                "confidence": "documented",
            },
        )
        entry["provenance"].append("documentation")
        entry.update({key: value for key, value in metadata.items() if value is not None})
    for name, metadata in defaults.items():
        entry = entries.setdefault(
            name,
            {
                "kind": "define",
                "type": scalar_type(str(metadata["default"])) if metadata["default"] is not True else "flag",
                "provenance": [],
                "confidence": "source",
            },
        )
        entry["provenance"].append("source")
        entry.update(metadata)
    for name in source_rules:
        if name in config_mapping and not config_mapping[name].get("invalid"):
            continue
        entry = entries.setdefault(
            name,
            {
                "provenance": [],
                "confidence": "source",
            },
        )
        entry["kind"] = "rule"
        entry["type"] = "bool"
        if "source" not in entry["provenance"]:
            entry["provenance"].append("source")
    for name in source_seen:
        entries.setdefault(
            name,
            {
                "kind": "define",
                "type": "flag",
                "provenance": ["source-reference"],
                "confidence": "source-reference",
            },
        )

    # This relationship is directly encoded by QMK's preprocessor condition;
    # record it mechanically rather than maintaining option-specific metadata.
    quick_source = (args.qmk / "quantum/action_tapping.h").read_text(errors="replace")
    if re.search(r"QUICK_TAP_TERM\s*>\s*TAPPING_TERM", quick_source):
        entries.setdefault("QUICK_TAP_TERM", {})["maximum"] = "TAPPING_TERM"

    config = json.loads(args.config.read_text())
    errors = []
    for name in config["qmk"]["defines"]:
        if name not in entries and name not in source_seen:
            errors.append(f"unknown QMK define: {name}")
    for name in config["qmk"]["rules"]:
        if name not in entries:
            errors.append(f"unknown QMK rule: {name}")
    if errors:
        raise SystemExit("\n".join(errors))

    args.output.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "qmk_revision": args.qmk_rev,
                "keycodes": keycodes,
                "options": dict(sorted(entries.items())),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
