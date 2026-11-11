"""Run CLIProxyAPI with private credentials rendered outside the Nix store."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--program", required=True)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--api-key-file", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    key = args.api_key_file.read_text().strip()
    if not key:
        raise SystemExit("CLIProxyAPI upstream key is empty")
    settings = json.loads(args.template.read_text())
    with tempfile.TemporaryDirectory(prefix="codex-cliproxyapi-", dir=os.environ.get("XDG_RUNTIME_DIR")) as temporary:
        directory = Path(temporary)
        settings["oauth"] = {"auth-dir": str(directory / "auth")}
        for providers in settings["api-keys"].values():
            for provider in providers:
                for credential in provider["keys"]:
                    credential["api-key"] = key
        config = directory / "config.json"
        config.write_text(json.dumps(settings))
        # JSON is a YAML subset. No YAML library or secret interpolation is needed.
        child = subprocess.Popen([args.program, "-config", str(config), "-local-model"], cwd=directory)
        def stop(signum, frame):
            child.send_signal(signum)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        return child.wait()


if __name__ == "__main__":
    raise SystemExit(main())
