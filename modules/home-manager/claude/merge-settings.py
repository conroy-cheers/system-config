"""Merge managed Claude JSON settings without replacing application state."""

import argparse
import json
import os
import tempfile
from pathlib import Path


def load(path, missing_ok=False):
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        if missing_ok:
            return {}
        raise
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return value


def remove_obsolete(existing, obsolete):
    for key, value in obsolete.items():
        if key not in existing:
            continue
        if isinstance(value, dict) and isinstance(existing[key], dict):
            remove_obsolete(existing[key], value)
        elif type(existing[key]) is type(value) and existing[key] == value:
            del existing[key]


def merge(existing, desired):
    for key, value in desired.items():
        if isinstance(value, dict) and isinstance(existing.get(key), dict):
            merge(existing[key], value)
        else:
            existing[key] = value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("--obsolete", type=Path)
    parser.add_argument("--profile-entry")
    args = parser.parse_args()
    desired, existing = load(args.source), load(args.target, missing_ok=True)
    if args.obsolete:
        remove_obsolete(existing, load(args.obsolete))
    if args.profile_entry:
        entries = existing.get("entries", [])
        if not isinstance(entries, list) or any(not isinstance(e, dict) for e in entries):
            raise ValueError("Expected desktop profile entries to be a list of objects")
        desired["entries"] = [e for e in entries if e.get("id") != args.profile_entry] + desired["entries"]
    merge(existing, desired)
    content = json.dumps(existing, indent=2) + "\n"
    if args.target.exists() and not args.target.is_symlink() and args.target.read_text() == content:
        return
    args.target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{args.target.name}.", dir=args.target.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(content)
        os.replace(temporary, args.target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
