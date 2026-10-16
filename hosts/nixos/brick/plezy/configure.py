"""Migrate Plezy to integrated SDR playback once, before it loads preferences."""

import json
import os
from pathlib import Path
import shutil
import tempfile


PROFILE = "brick-integrated-mpv-v1"
MARKER = "nixos_integrated_mpv_profile"
OPTIONS = {"hdr-compute-peak": "yes", "contrast": "10"}


def configure(data_home):
    directory = data_home / "com.edde746.plezy"
    path = directory / "shared_preferences.json"
    preferences = json.loads(path.read_text()) if path.exists() else {}
    if preferences.get(MARKER) == PROFILE:
        return

    # A live Flutter instance caches this file and could overwrite a migration.
    # A second launch can activate that instance; defer changes until it exits.
    for process in Path("/proc").glob("[0-9]*"):
        try:
            if process.joinpath("comm").read_text().strip() != ".plezy-wrapped":
                continue
            environment = dict(
                item.split(b"=", 1)
                for item in process.joinpath("environ").read_bytes().split(b"\0")
                if b"=" in item
            )
            process_home = Path(os.fsdecode(environment.get(b"HOME", b"/nonexistent")))
            process_data = Path(
                os.fsdecode(environment.get(b"XDG_DATA_HOME", os.fsencode(process_home / ".local/share")))
            )
            if process_data == data_home:
                print("Plezy's integrated player will be configured after the running instance exits.")
                return
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

    # Preserve existing custom options, including the legacy list format.
    text = preferences.get("mpv_config_text")
    if text is None:
        entries = json.loads(preferences.get("mpv_config_entries", "[]"))
        text = "\n".join(
            ("" if entry.get("isEnabled", True) else "#") + f"{entry['key']}={entry.get('value', '')}"
            for entry in entries
            if entry.get("key")
        )
    lines = [line for line in text.splitlines() if line.split("=", 1)[0].strip() not in OPTIONS]
    lines.extend(f"{key}={value}" for key, value in OPTIONS.items())
    preferences.update(
        use_external_player=False,
        enable_hdr=False,
        mpv_config_text="\n".join(lines) + "\n",
    )
    preferences[MARKER] = PROFILE

    directory.mkdir(parents=True, exist_ok=True)
    backup = directory / "shared_preferences.before-integrated-mpv.json"
    if path.exists() and not backup.exists():
        with backup.open("xb") as output:
            os.chmod(backup, 0o600)
            with path.open("rb") as source:
                shutil.copyfileobj(source, output)
    fd, temporary = tempfile.mkstemp(prefix=".shared_preferences.", dir=directory)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(preferences, output, ensure_ascii=False, indent=2)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    configure(Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")))
