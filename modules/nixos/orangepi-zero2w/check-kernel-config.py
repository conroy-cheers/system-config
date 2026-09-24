#!/usr/bin/env python3
"""Reject kernel-config drift that would silently enlarge the board closure."""

import argparse
import pathlib
import re


def parse_config(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if match := re.fullmatch(r"CONFIG_([A-Z0-9_]+)=(.+)", line):
            values[match.group(1)] = match.group(2)
        elif match := re.fullmatch(r"# CONFIG_([A-Z0-9_]+) is not set", line):
            values[match.group(1)] = "n"
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=pathlib.Path, required=True)
    parser.add_argument("--disabled", type=pathlib.Path, required=True)
    parser.add_argument("--allow-drm", action="append", default=[])
    parser.add_argument("--require", action="append", default=[])
    args = parser.parse_args()

    config = parse_config(args.config)
    errors: list[str] = []

    for requirement in args.require:
        symbol, expected = requirement.split("=", 1)
        actual = config.get(symbol, "absent")
        if actual != expected:
            errors.append(f"CONFIG_{symbol}: expected {expected}, got {actual}")

    for symbol in args.disabled.read_text().split():
        if config.get(symbol) in {"y", "m"}:
            errors.append(f"CONFIG_{symbol} unexpectedly enabled as {config[symbol]}")

    allowed = set(args.allow_drm)
    for symbol, value in config.items():
        if symbol.startswith("DRM_") and value in {"y", "m"} and symbol not in allowed:
            errors.append(f"CONFIG_{symbol}={value} is not in the DRM allow-list")

    if errors:
        raise SystemExit("kernel configuration check failed:\n  " + "\n  ".join(errors))


if __name__ == "__main__":
    main()
