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
import urllib.parse
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


def validate(config, directory, validation_home, catalog, env):
    expected_ids = model_ids(catalog)
    candidate = directory / "models.json"
    atomic_json(candidate, catalog)
    # Validate against this instance's actual Codex version without remote fetches.
    (validation_home / "config.toml").write_text(
        "model_catalog_json = " + json.dumps(str(candidate)) + "\n"
    )
    validated = json.loads(run([config["codex"], "debug", "models"], env))
    if set(model_ids(validated)) != set(expected_ids):
        raise ValueError("Codex did not load the discovered catalog")
    return catalog


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
    if config.get("backend") == "cliproxyapi":
        # CLIProxyAPI serves its native Codex catalog for Codex user agents.
        version = config.get("client_version", "0")
        headers["User-Agent"] = "codex_cli_rs/" + version
        url += "?" + urllib.parse.urlencode({"client_version": version})
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=10) as response:
            catalog = json.load(response)
        ids = model_ids(catalog)
        routes = {route.get("alias") or route["name"]: route for route in config.get("routes", [])}
        if routes and set(ids) != set(routes):
            raise ValueError("CLIProxyAPI has not loaded the configured model routes")
        for model in catalog["models"]:
            levels = routes.get(model["slug"], {}).get("thinking", {}).get("levels")
            if levels is not None and set(levels) != {level["effort"] for level in model.get("supported_reasoning_levels", [])}:
                raise ValueError("CLIProxyAPI has not loaded the configured reasoning levels")
            overrides = config["overrides"].get(model["slug"], {})
            if "slug" in overrides:
                raise ValueError("model overrides must not change slug")
            model.update(overrides)
        return validate(config, directory, validation_home, catalog, env)
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
    # The relay clears reasoning capabilities, even for known Codex models.
    # Match after prefix removal so azure/<model> retains its native controls.
    bundled = json.loads(run([config["codex"], "debug", "models", "--bundled"], env))
    bundled_by_id = {model["slug"]: model for model in bundled["models"]}
    by_id = {model["slug"]: model for model in catalog["models"]}
    models = []
    for slug in advertised:
        if slug not in by_id:
            raise ValueError("relay catalog is missing a discovered model; refusing fallback metadata")
        model = by_id[slug].copy()
        normalized = slug[len(prefix):]
        model["slug"] = normalized
        model["display_name"] = normalized
        known = bundled_by_id.get(normalized)
        if known is not None:
            model["default_reasoning_level"] = known.get("default_reasoning_level")
            model["supported_reasoning_levels"] = known.get("supported_reasoning_levels", [])
        allowed_efforts = config.get("reasoning_efforts")
        if allowed_efforts is not None:
            model["supported_reasoning_levels"] = [
                level for level in model.get("supported_reasoning_levels", [])
                if level["effort"] in allowed_efforts
            ]
            efforts = [level["effort"] for level in model["supported_reasoning_levels"]]
            if model.get("default_reasoning_level") not in efforts:
                model["default_reasoning_level"] = efforts[0] if efforts else None
        overrides = config["overrides"].get(normalized, {})
        if "slug" in overrides:
            raise ValueError("model overrides must not change slug")
        model.update(overrides)
        models.append(model)
    catalog["models"] = models
    return validate(config, directory, validation_home, catalog, env)


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
        backoff = 0 if config.get("backend") == "cliproxyapi" and not usable else 300
        if not force and state.get("fingerprint") == fingerprint and now - state.get("last_attempt", 0) < backoff:
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


def uses_relay(arguments, default_relay):
    profile = selected_profile(arguments)
    return profile == "chat-completions" or (profile is None and default_relay)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--if-stale", action="store_true")
    parser.add_argument("--allow-missing", action="store_true", help="do not block activation or native-provider desktop startup")
    parser.add_argument("--for-codex", nargs=argparse.REMAINDER, help="refresh when the relay is selected explicitly or by default")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        config = json.loads(args.config.read_text())
        if args.for_codex is not None and not uses_relay(args.for_codex, config.get("default_relay", False)):
            return 0
        success = refresh(config, force=not args.if_stale and args.for_codex is None)
    except (OSError, ValueError):
        print("Cannot prepare Codex relay catalog", file=sys.stderr)
        success = False
    if not success and not args.allow_missing:
        print("No usable relay model catalog; connect to the gateway and run the refresh command again", file=sys.stderr)
    return 0 if success or args.allow_missing else 1


if __name__ == "__main__":
    sys.exit(main())
