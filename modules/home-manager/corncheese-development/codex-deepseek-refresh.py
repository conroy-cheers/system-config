"""Refresh DeepSeek's Codex metadata without executing its installer."""

import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


SOURCE_URL = "https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh"
MAX_AGE = 24 * 60 * 60
RETRY_DELAY = 5 * 60
DEFAULT_MODEL = "deepseek-flash"
REQUIRED_FIELDS = {
    "slug", "display_name", "supported_reasoning_levels", "shell_type",
    "visibility", "supported_in_api", "priority", "support_verbosity",
    "truncation_policy", "context_window", "input_modalities",
}
# Only these capability fields may change remotely. In particular, instructions,
# approval policies, tool overrides and service tiers remain locally controlled.
STRING_FIELDS = {"slug", "display_name"}
OPTIONAL_STRING_FIELDS = {"description", "comp_hash"}
BOOL_FIELDS = {
    "supported_in_api", "support_verbosity", "supports_image_detail_original",
    "supports_search_tool", "supports_reasoning_summary_parameter",
}
POSITIVE_FIELDS = {"context_window", "max_context_window", "auto_compact_token_limit"}
ENUM_FIELDS = {
    "shell_type": {"shell_command", "unified_exec", "default", "local", "disabled"},
    "visibility": {"list", "hide", "none"},
    "default_reasoning_level": {None, "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"},
    "default_reasoning_summary": {"none", "auto", "concise", "detailed"},
    "default_verbosity": {None, "low", "medium", "high"},
    "apply_patch_tool_type": {None, "freeform"},
    "web_search_tool_type": {"text", "text_and_image"},
}
CAPABILITY_FIELDS = (
    STRING_FIELDS | OPTIONAL_STRING_FIELDS | BOOL_FIELDS | POSITIVE_FIELDS
    | ENUM_FIELDS.keys()
    | {"priority", "effective_context_window_percent", "supported_reasoning_levels",
       "truncation_policy", "input_modalities", "minimal_client_version"}
)


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError("invalid minimum client version")
    return tuple(map(int, value.split(".")))


def valid_field(key, value):
    if key in STRING_FIELDS:
        return isinstance(value, str) and bool(value.strip())
    if key in OPTIONAL_STRING_FIELDS:
        return value is None or isinstance(value, str)
    if key in BOOL_FIELDS:
        return type(value) is bool
    if key in POSITIVE_FIELDS:
        return value is None or (type(value) is int and 0 < value < 2**63)
    if key in ENUM_FIELDS:
        return (value is None or isinstance(value, str)) and value in ENUM_FIELDS[key]
    if key == "priority":
        return type(value) is int and -(2**31) <= value < 2**31
    if key == "effective_context_window_percent":
        return type(value) is int and 0 < value <= 100
    if key == "minimal_client_version":
        version_tuple(value)
        return True
    if key == "input_modalities":
        return isinstance(value, list) and bool(value) and all(
            isinstance(item, str) and item in {"text", "image"} for item in value
        ) and "text" in value
    if key == "truncation_policy":
        return (
            isinstance(value, dict) and value.get("mode") in ("bytes", "tokens")
            and type(value.get("limit")) is int and 0 < value["limit"] < 2**63
        )
    if key == "supported_reasoning_levels":
        return isinstance(value, list) and bool(value) and all(
            isinstance(item, dict)
            and isinstance(item.get("effort"), str)
            and item["effort"] in ENUM_FIELDS["default_reasoning_level"]
            and isinstance(item.get("description"), str)
            for item in value
        )
    return False


def normalize_catalog(data, bundled, instructions, client_version):
    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, list) or not 0 < len(models) <= 100:
        raise ValueError("catalog must contain 1–100 models")
    templates = {model["slug"]: model for model in bundled["models"]}
    result = []
    seen = set()
    for source in models:
        if not isinstance(source, dict) or not REQUIRED_FIELDS <= source.keys():
            raise ValueError("model is missing required capability fields")
        for key in CAPABILITY_FIELDS & source.keys():
            if not valid_field(key, source[key]):
                raise ValueError(f"invalid model capability: {key}")
        slug = source["slug"]
        if not re.fullmatch(r"deepseek-[a-zA-Z0-9._-]+", slug) or slug in seen:
            raise ValueError("invalid or duplicate DeepSeek model ID")
        seen.add(slug)
        minimum = source.get("minimal_client_version", "0.0.0")
        if version_tuple(minimum) > version_tuple(client_version):
            raise ValueError(f"{slug} requires Codex {minimum}; installed: {client_version}")
        model = copy.deepcopy(templates.get(slug, templates[DEFAULT_MODEL]))
        model.update({key: source[key] for key in CAPABILITY_FIELDS & source.keys()})
        efforts = {level["effort"] for level in model["supported_reasoning_levels"]}
        if model.get("default_reasoning_level") not in efforts:
            raise ValueError(f"{slug} has an unsupported default reasoning effort")
        if model["context_window"] is None:
            raise ValueError(f"{slug} has no context window")
        maximum = model.get("max_context_window")
        if maximum is not None and maximum < model["context_window"]:
            raise ValueError(f"{slug} context window exceeds its maximum")
        # Replace the entire message object: remote fields can also contain
        # tool instructions, approval policies and subagent prompts.
        model.pop("base_instructions", None)
        model["model_messages"] = {"instructions_template": instructions}
        result.append(model)
    default = next((model for model in result if model["slug"] == DEFAULT_MODEL), None)
    if default is None or default["visibility"] != "list" or not default["supported_in_api"]:
        raise ValueError("catalog no longer supports the configured default model")
    if "high" not in {level["effort"] for level in default["supported_reasoning_levels"]}:
        raise ValueError("default model no longer supports the profile's reasoning effort")
    return {"models": result}


def extract_catalog(script):
    blocks = re.findall(
        r"<<'CODEX_MODELS_JSON'\r?\n(.*?)\r?\nCODEX_MODELS_JSON(?:\r?\n|$)",
        script, re.DOTALL,
    )
    if len(blocks) != 1:
        raise ValueError("installer no longer contains one CODEX_MODELS_JSON block")
    return json.loads(blocks[0])


def download_catalog(curl):
    response = subprocess.run(
        [curl, "--fail", "--silent", "--show-error", "--location",
         "--proto", "=https", "--proto-redir", "=https",
         "--connect-timeout", "2", "--max-time", "5", "--max-filesize", "2097152",
         SOURCE_URL],
        capture_output=True, text=True, timeout=6, check=True,
    )
    return extract_catalog(response.stdout)


def atomic_json(path, data):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(data, stream, indent=2, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def refresh(cache, bundled, instructions, client_version, fetch, *, force=False, seed_only=False):
    cache.parent.mkdir(parents=True, exist_ok=True)
    # Concurrent starts share one fetch and never see a partially written catalog.
    with cache.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        existing = read_json(cache)
        try:
            current = normalize_catalog(existing, bundled, instructions, client_version)
            recovered = False
        except ValueError:
            current = normalize_catalog(bundled, bundled, instructions, client_version)
            recovered = True
        if current != existing:
            atomic_json(cache, current)
        if seed_only:
            return True
        state_path = cache.with_suffix(".state.json")
        state = read_json(state_path)
        if not isinstance(state, dict):
            state = {}
        now = time.time()

        def recent(key, age):
            timestamp = state.get(key)
            return type(timestamp) in (int, float) and 0 <= now - timestamp < age

        if not force and not recovered and (
            recent("last_success", MAX_AGE) or recent("last_attempt", RETRY_DELAY)
        ):
            return True
        state["last_attempt"] = now
        try:
            updated = normalize_catalog(fetch(), bundled, instructions, client_version)
            atomic_json(cache, updated)
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            # Record a short retry delay so offline launches do not all wait five seconds.
            atomic_json(state_path, state)
            print(f"DeepSeek catalog refresh failed; using cached catalog: {error}", file=sys.stderr)
            return False
        state["last_success"] = now
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
    parser.add_argument("--cache-file", type=Path, required=True)
    parser.add_argument("--bundled-catalog", type=Path, required=True)
    parser.add_argument("--instructions", type=Path, required=True)
    parser.add_argument("--client-version", required=True)
    parser.add_argument("--curl", required=True)
    parser.add_argument("--seed-only", action="store_true", help="initialize the cache without network access")
    parser.add_argument("--if-stale", action="store_true", help="respect the 24-hour cache and retry delay")
    parser.add_argument("--for-codex", nargs=argparse.REMAINDER, help="refresh only for --profile deepseek")
    args = parser.parse_args()
    if args.for_codex is not None and selected_profile(args.for_codex) != "deepseek":
        return 0
    try:
        success = refresh(
            args.cache_file, json.loads(args.bundled_catalog.read_text()),
            args.instructions.read_text(), args.client_version,
            lambda: download_catalog(args.curl),
            force=not args.if_stale and args.for_codex is None,
            seed_only=args.seed_only,
        )
    except (ValueError, OSError) as error:
        print(f"Cannot prepare DeepSeek catalog: {error}", file=sys.stderr)
        return 1
    if args.for_codex is not None:
        return 0  # Download failures have a usable, validated fallback.
    if success and not args.seed_only:
        print(f"DeepSeek catalog ready: {args.cache_file}")
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
