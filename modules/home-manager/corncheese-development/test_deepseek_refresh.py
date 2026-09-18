import copy
import importlib.util
import io
import json
import multiprocessing
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch


ROOT = Path(__file__).parent
spec = importlib.util.spec_from_file_location("refresh", ROOT / "codex-deepseek-refresh.py")
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)
BUNDLED = json.loads((ROOT / "deepseek-models.json").read_text())
INSTRUCTIONS = (ROOT / "deepseek-instructions.txt").read_text()
VERSION = "0.155.0"


def concurrent_refresh(cache, counter):
    def fetch():
        with counter.open("a") as stream:
            stream.write("fetch\n")
        time.sleep(0.1)
        return BUNDLED

    refresh.refresh(cache, BUNDLED, INSTRUCTIONS, VERSION, fetch)


class CatalogTests(unittest.TestCase):
    def normalize(self, data):
        return refresh.normalize_catalog(data, BUNDLED, INSTRUCTIONS, VERSION)

    def test_extracts_data_without_executing_installer(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "executed"
            script = (
                f"touch {marker}\ncat <<'CODEX_MODELS_JSON'\n"
                + json.dumps(BUNDLED) + "\nCODEX_MODELS_JSON\n"
            )
            self.assertEqual(refresh.extract_catalog(script), BUNDLED)
            self.assertFalse(marker.exists())
            with self.assertRaises(ValueError):
                refresh.extract_catalog(script + script)
            with self.assertRaises(ValueError):
                refresh.extract_catalog("upstream changed its installer format")

    def test_updates_capabilities_and_adds_models_but_pins_instructions(self):
        remote = copy.deepcopy(BUNDLED)
        model = remote["models"][0]
        model["context_window"] = 500000
        model["model_messages"] = {"instructions_template": "unreviewed prompt", "approvals": {}}
        model["base_instructions"] = "another unreviewed prompt"
        model["guardian"] = {}
        model["auto_review_model_override"] = "different-provider-model"
        new_model = copy.deepcopy(model)
        new_model["slug"] = "deepseek-future"
        remote["models"].append(new_model)
        normalized = self.normalize(remote)
        self.assertEqual(len(normalized["models"]), 3)
        self.assertEqual(normalized["models"][0]["context_window"], 500000)
        for model in normalized["models"]:
            self.assertEqual(model["model_messages"], {"instructions_template": INSTRUCTIONS})
            self.assertNotIn("base_instructions", model)
            self.assertNotIn("guardian", model)
            self.assertIsNone(model["auto_review_model_override"])

    def test_rejects_incompatible_metadata(self):
        for field, value in (
            ("context_window", True), ("context_window", -1), ("context_window", None),
            ("supported_reasoning_levels", []), ("shell_type", "unknown"),
            ("input_modalities", ["audio"]), ("visibility", "hide"),
            ("minimal_client_version", "99.0.0"), ("minimal_client_version", "invalid"),
            ("priority", 2**40), ("supported_in_api", "true"),
            ("max_context_window", 1),
        ):
            with self.subTest(field=field, value=value):
                data = copy.deepcopy(BUNDLED)
                data["models"][0][field] = value
                with self.assertRaises(ValueError):
                    self.normalize(data)
        for data in (None, {}, {"models": []}, {"models": [{}]},
                     {"models": [BUNDLED["models"][1]]},
                     {"models": [BUNDLED["models"][0]] * 2}):
            with self.subTest(data=data):
                with self.assertRaises(ValueError):
                    self.normalize(data)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cache = Path(self.directory.name) / "nested" / "models.json"

    def run_refresh(self, fetch=lambda: BUNDLED, **kwargs):
        return refresh.refresh(self.cache, BUNDLED, INSTRUCTIONS, VERSION, fetch, **kwargs)

    def test_first_run_offline_seeds_fallback_and_backs_off(self):
        def offline():
            raise subprocess.TimeoutExpired("curl", 6)

        with redirect_stderr(io.StringIO()):
            self.assertFalse(self.run_refresh(offline))
        self.assertEqual(json.loads(self.cache.read_text())["models"][0]["slug"], "deepseek-flash")
        self.assertTrue(self.run_refresh(lambda: self.fail("retried during backoff")))

    def test_fresh_cache_skips_fetch_and_force_refreshes(self):
        with patch.object(refresh.time, "time", return_value=100000):
            self.run_refresh()
        with patch.object(refresh.time, "time", return_value=100100):
            self.assertTrue(self.run_refresh(lambda: self.fail("fetched a fresh catalog")))
        calls = []
        self.run_refresh(lambda: calls.append(True) or BUNDLED, force=True)
        self.assertEqual(calls, [True])

    def test_stale_cache_refreshes(self):
        with patch.object(refresh.time, "time", return_value=100000):
            self.run_refresh()
        remote = copy.deepcopy(BUNDLED)
        remote["models"][0]["description"] = "updated"
        with patch.object(refresh.time, "time", return_value=100000 + refresh.MAX_AGE + 1):
            self.run_refresh(lambda: remote)
        self.assertEqual(json.loads(self.cache.read_text())["models"][0]["description"], "updated")

    def test_bad_refresh_preserves_last_valid_cache(self):
        self.run_refresh()
        previous = self.cache.read_bytes()
        with redirect_stderr(io.StringIO()):
            self.assertFalse(self.run_refresh(lambda: {"models": []}, force=True))
        self.assertEqual(self.cache.read_bytes(), previous)

    def test_seed_repairs_corruption_and_reapplies_pinned_instructions_offline(self):
        self.cache.parent.mkdir()
        self.cache.write_text("broken JSON")
        self.run_refresh(lambda: self.fail("seed contacted network"), seed_only=True)
        cached = json.loads(self.cache.read_text())
        cached["models"][0]["model_messages"] = {"instructions_template": "old instructions"}
        self.cache.write_text(json.dumps(cached))
        self.run_refresh(lambda: self.fail("seed contacted network"), seed_only=True)
        self.assertEqual(json.loads(self.cache.read_text())["models"][0]["model_messages"],
                         {"instructions_template": INSTRUCTIONS})

    def test_atomic_write_failure_preserves_previous_file(self):
        self.run_refresh(seed_only=True)
        previous = self.cache.read_bytes()
        with patch.object(refresh.os, "replace", side_effect=OSError("write failed")):
            with self.assertRaises(OSError):
                refresh.atomic_json(self.cache, {"models": []})
        self.assertEqual(self.cache.read_bytes(), previous)
        self.assertEqual(sorted(path.name for path in self.cache.parent.iterdir()),
                         ["models.json", "models.lock"])

    def test_concurrent_launches_share_one_fetch(self):
        # Linux and macOS both support flock; fork keeps this test independent of
        # the import name used for the installed script.
        context = multiprocessing.get_context("fork")
        counter = Path(self.directory.name) / "fetches"
        processes = [context.Process(target=concurrent_refresh, args=(self.cache, counter))
                     for _ in range(3)]
        for process in processes:
            process.start()
        for process in processes:
            process.join(timeout=10)
            if process.is_alive():
                process.kill()
                self.fail("concurrent refresh did not finish")
            self.assertEqual(process.exitcode, 0)
        self.assertEqual(counter.read_text().splitlines(), ["fetch"])
        self.assertEqual(len(json.loads(self.cache.read_text())["models"]), 2)


class LaunchTests(unittest.TestCase):
    def test_profile_detection(self):
        for arguments in (
            ["--profile", "deepseek"], ["-p", "deepseek"], ["-pdeepseek"],
            ["exec", "--profile=deepseek", "review this"],
            ["--profile", "deepseek", "exec", "--model", "deepseek-v4-pro"],
        ):
            self.assertEqual(refresh.selected_profile(arguments), "deepseek")
        for arguments in (
            [], ["--profile", "other"], ["exec", "--", "--profile", "deepseek"],
            ["exec", "the text --profile deepseek"], ["--config", "--profile=deepseek"],
        ):
            self.assertNotEqual(refresh.selected_profile(arguments), "deepseek")


if __name__ == "__main__":
    unittest.main()
