"""Merge managed TOML leaves while preserving mutable Codex settings/comments."""

import json
import os
import sys
import tempfile
from pathlib import Path

import tomlkit


def merge_config(existing, desired):
    for key, value in desired.items():
        if key in existing and hasattr(existing[key], "items") and hasattr(value, "items"):
            merge_config(existing[key], value)
        else:
            existing[key] = value


def main():
    source, target = map(Path, sys.argv[1:3])
    desired = tomlkit.parse(source.read_text())
    try:
        existing = tomlkit.parse(target.read_text())
    except FileNotFoundError:
        existing = tomlkit.document()
    merge_config(existing, desired)
    for path in json.loads(sys.argv[3]):
        parent = existing
        for key in path[:-1]:
            parent = parent.get(key, {}) if hasattr(parent, "get") else {}
        if path and hasattr(parent, "pop"):
            parent.pop(path[-1], None)

    target.parent.mkdir(parents=True, exist_ok=True)
    # Replace old managed symlinks without touching their store targets. mkstemp
    # also keeps credentials in config.toml private and avoids temporary-name races.
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(tomlkit.dumps(existing))
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    main()
