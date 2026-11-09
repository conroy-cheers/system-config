"""Prepare a per-instance Codex catalog using codex-relay's metadata generator."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.error
import urllib.request


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output)
            output.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def model_ids(catalog):
    models = catalog.get("models") if isinstance(catalog, dict) else None
    if not isinstance(models, list) or not models:
        raise ValueError("catalog contains no models")
    ids = [model.get("slug") if isinstance(model, dict) else None for model in models]
    if any(not isinstance(slug, str) or not slug.strip() or slug.startswith("<") for slug in ids):
        raise ValueError("catalog contains an invalid model ID")
    if len(ids) != len(set(ids)):
        raise ValueError("catalog contains duplicate model IDs")
    return ids


def run(command, env):
    result = subprocess.run(command, env=env, capture_output=True, timeout=20)
    if result.returncode:
        # Do not print subprocess output: provider errors can include credentials.
        raise ValueError(f"{Path(command[0]).name} exited with status {result.returncode}")
    return result.stdout


def generate(config, directory):
    env = os.environ.copy()
    env["PATH"] = str(Path(config["codex"]).parent) + os.pathsep + env.get("PATH", "")
    validation_home = directory / "codex-home"
    validation_home.mkdir()
    env["CODEX_HOME"] = str(validation_home)
    env.pop("CODEX_RELAY_API_KEY", None)
    headers = {}
    if config["api_key_file"] is not None:
        key = Path(config["api_key_file"]).read_text().strip()
        if not key:
            raise ValueError("API key file is empty")
        env["CODEX_RELAY_API_KEY"] = key
        headers["Authorization"] = f"Bearer {key}"
    url = config["upstream"].rstrip("/") + "/models"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.load(response)
    entries = payload.get("data", payload.get("models")) if isinstance(payload, dict) else None
    if not isinstance(entries, list):
        raise ValueError("discovery response has no model list")
    prefix = config["strip_prefix"]
    advertised = []
    for entry in entries:
        slug = entry.get("id") if isinstance(entry, dict) else None
        if not isinstance(slug, str) or not slug.strip() or slug.startswith("<"):
            raise ValueError("discovery response contains an invalid model ID")
        if slug.startswith(prefix):
            advertised.append(slug)
    if not advertised or len(advertised) != len(set(advertised)):
        raise ValueError("discovery response contains no matching models or duplicate IDs")

    generated = directory / "generated.json"
    command = [config["relay"], "--print-config", "--upstream", config["upstream"],
               "--model-catalog", str(generated)]
    if config["model_template"] is not None:
        command += ["--model-template", config["model_template"]]
    snippet = tomllib.loads(run(command, env).decode())
    if not isinstance(snippet.get("model"), str) or snippet["model"].startswith("<"):
        raise ValueError("relay could not fetch the model list")
    catalog = read_json(generated)
    model_ids(catalog)
    by_id = {model["slug"]: model for model in catalog["models"]}
    models = []
    for slug in advertised:
        if slug not in by_id:
            raise ValueError("relay catalog is missing a discovered model; refusing fallback metadata")
        model = by_id[slug].copy()
        normalized = slug[len(prefix):]
        model["slug"] = normalized
        model["display_name"] = normalized
        overrides = config["overrides"].get(normalized, {})
        if "slug" in overrides:
            raise ValueError("model overrides must not change slug")
        model.update(overrides)
        models.append(model)
    catalog["models"] = models
    expected_ids = model_ids(catalog)
    candidate = directory / "models.json"
    atomic_json(candidate, catalog)

    # Validate metadata with this instance's actual Codex version. An isolated
    # CODEX_HOME and explicit local catalog prevent config hooks or remote fetches.
    (validation_home / "config.toml").write_text(
        "model_catalog_json = " + json.dumps(str(candidate)) + "\n"
    )
    validated = json.loads(run([config["codex"], "debug", "models"], env))
    if set(model_ids(validated)) != set(expected_ids):
        raise ValueError("Codex did not load the discovered catalog")
    return catalog


def refresh(config, *, force=False):
    cache = Path(config["cache_file"])
    cache.parent.mkdir(parents=True, exist_ok=True)
    state_path = cache.with_suffix(".state.json")
    fingerprint = hashlib.sha256(
        json.dumps(config, sort_keys=True).encode() + Path(__file__).read_bytes()
    ).hexdigest()
    with cache.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = read_json(state_path)
        if not isinstance(state, dict):
            state = {}
        cached = read_json(cache)
        try:
            model_ids(cached)
            usable = state.get("catalog_fingerprint") == fingerprint
        except ValueError:
            usable = False
        now = time.time()
        if not force and usable and now - state.get("last_success", 0) < config["refresh_interval"]:
            return True
        if not force and state.get("fingerprint") == fingerprint and now - state.get("last_attempt", 0) < 300:
            return usable
        # A changed configuration must not mark an old catalog as usable.
        if state.get("fingerprint") != fingerprint:
            state = {"fingerprint": fingerprint}
        state["last_attempt"] = now
        atomic_json(state_path, state)
        try:
            with tempfile.TemporaryDirectory(prefix=".refresh-", dir=cache.parent) as temporary:
                catalog = generate(config, Path(temporary))
            atomic_json(cache, catalog)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            if isinstance(error, urllib.error.HTTPError):
                error.close()
            status = "using cached catalog" if usable else "no usable catalog; connect to the gateway and retry"
            print(f"Codex relay catalog refresh failed; {status}", file=sys.stderr)
            return usable
        state["last_success"] = now
        state["catalog_fingerprint"] = fingerprint
        atomic_json(state_path, state)
        return True


def selected_profile(arguments):
    profile = None
    args = iter(arguments)
    for argument in args:
        if argument == "--":
            break
        if argument in ("-p", "--profile"):
            profile = next(args, None)
        elif argument.startswith("--profile="):
            profile = argument.split("=", 1)[1]
        elif argument.startswith("-p") and not argument.startswith("--"):
            profile = argument[2:]
        elif argument in ("-c", "--config", "-m", "--model", "-C", "--cd", "-i", "--image"):
            next(args, None)
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--if-stale", action="store_true")
    parser.add_argument("--allow-missing", action="store_true", help="do not block activation or native-provider desktop startup")
    parser.add_argument("--for-codex", nargs=argparse.REMAINDER, help="refresh only for --profile chat-completions")
    args = parser.parse_args()
    if args.for_codex is not None and selected_profile(args.for_codex) != "chat-completions":
        return 0
    os.umask(0o077)
    try:
        config = json.loads(args.config.read_text())
        success = refresh(config, force=not args.if_stale and args.for_codex is None)
    except (OSError, ValueError):
        print("Cannot prepare Codex relay catalog", file=sys.stderr)
        success = False
    if not success and not args.allow_missing:
        print("No usable relay model catalog; connect to the gateway and run the refresh command again", file=sys.stderr)
    return 0 if success or args.allow_missing else 1


if __name__ == "__main__":
    sys.exit(main())
