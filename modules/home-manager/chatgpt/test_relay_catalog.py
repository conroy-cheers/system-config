"""Integration tests using the real relay/Codex binaries and a local models API."""

from concurrent.futures import ThreadPoolExecutor
import http.server
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest


spec = importlib.util.spec_from_file_location("catalog", Path(__file__).with_name("refresh-relay-catalog.py"))
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class ModelsHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.server.requests += 1
        self.server.headers_seen.append(self.headers.get("Authorization"))
        if self.path != "/gateway/v1/models" or self.server.fail_after < self.server.requests:
            self.send_error(503)
            return
        payload = json.dumps(self.server.payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


@unittest.skipUnless(os.environ.get("CODEX_RELAY_TEST_CODEX") and os.environ.get("CODEX_RELAY_TEST_RELAY"),
                     "set CODEX_RELAY_TEST_CODEX and CODEX_RELAY_TEST_RELAY to the actual binaries")
class CatalogIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ModelsHandler)
        self.server.payload = {"data": [
            {"id": "azure/DeepSeek-V4.1-Flash"}, {"id": "azure/gpt-6-astra"},
            {"id": "other/not-for-this-provider"},
        ]}
        self.server.requests = 0
        self.server.fail_after = float("inf")
        self.server.headers_seen = []
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        key = root / "key"
        key.write_text("test-relay-token\n")
        self.cache = root / "cache" / "models.json"
        self.config = {
            "cache_file": str(self.cache),
            "codex": os.environ["CODEX_RELAY_TEST_CODEX"],
            "relay": os.environ["CODEX_RELAY_TEST_RELAY"],
            "api_key_file": str(key),
            "upstream": f"http://127.0.0.1:{self.server.server_port}/gateway/v1/",
            "strip_prefix": "azure/",
            "model_template": None,
            "overrides": {"DeepSeek-V4.1-Flash": {"context_window": 131072}},
            "refresh_interval": 86400,
        }

    def test_real_generation_filtering_overrides_and_codex_validation(self):
        self.assertTrue(catalog.refresh(self.config))
        models = json.loads(self.cache.read_text())["models"]
        self.assertEqual([m["slug"] for m in models], ["DeepSeek-V4.1-Flash", "gpt-6-astra"])
        self.assertEqual(models[0]["context_window"], 131072)
        self.assertIn("shell_type", models[0])
        self.assertEqual(self.server.headers_seen, ["Bearer test-relay-token"] * 2)
        self.assertEqual(self.cache.stat().st_mode & 0o777, 0o600)

    def test_fresh_cache_and_concurrent_refresh_do_not_refetch(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(list(pool.map(lambda _: catalog.refresh(self.config), range(2))), [True, True])
        self.assertTrue(catalog.refresh(self.config))
        self.assertEqual(self.server.requests, 2)

    def test_generic_public_api_without_a_model_prefix(self):
        self.server.payload = {"data": [{"id": "custom-model"}]}
        self.config.update(api_key_file=None, strip_prefix="", overrides={})
        self.assertTrue(catalog.refresh(self.config))
        self.assertEqual(catalog.model_ids(json.loads(self.cache.read_text())), ["custom-model"])
        self.assertEqual(self.server.headers_seen, [None, None])

    def test_failed_refresh_preserves_last_success_and_backs_off(self):
        self.assertTrue(catalog.refresh(self.config))
        before = self.cache.read_bytes()
        state_path = self.cache.with_suffix(".state.json")
        state = json.loads(state_path.read_text())
        state["last_success"] = 0
        state_path.write_text(json.dumps(state))
        self.server.fail_after = 0
        self.assertTrue(catalog.refresh(self.config, force=True))
        self.assertEqual(self.cache.read_bytes(), before)
        self.assertTrue(catalog.refresh(self.config))
        self.assertEqual(self.server.requests, 3)

    def test_first_failure_has_no_fake_catalog(self):
        self.server.payload = {"data": []}
        self.assertFalse(catalog.refresh(self.config, force=True))
        self.assertFalse(self.cache.exists())

    def test_relay_fallback_cannot_replace_a_valid_catalog(self):
        self.assertTrue(catalog.refresh(self.config))
        before = self.cache.read_bytes()
        # The discovery preflight succeeds but the relay's own fetch fails.
        self.server.fail_after = self.server.requests + 1
        self.assertTrue(catalog.refresh(self.config, force=True))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_changed_configuration_cannot_reuse_old_catalog_after_failure(self):
        self.assertTrue(catalog.refresh(self.config))
        before = self.cache.read_bytes()
        self.config["overrides"] = {"DeepSeek-V4.1-Flash": {"context_window": "invalid"}}
        self.assertFalse(catalog.refresh(self.config, force=True))
        self.assertFalse(catalog.refresh(self.config))
        self.assertEqual(self.cache.read_bytes(), before)

    def test_invalid_response_does_not_erase_catalog(self):
        self.assertTrue(catalog.refresh(self.config))
        before = self.cache.read_bytes()
        for payload in ([], {"data": [{"id": "azure/"}]}, {"data": [{"id": "azure/a"}] * 2}):
            self.server.payload = payload
            self.assertTrue(catalog.refresh(self.config, force=True))
            self.assertEqual(self.cache.read_bytes(), before)


class ProfileSelectionTests(unittest.TestCase):
    def test_default_relay_and_explicit_profile_selection(self):
        self.assertTrue(catalog.uses_relay([], True))
        self.assertTrue(catalog.uses_relay(["exec", "prompt"], True))
        self.assertFalse(catalog.uses_relay([], False))
        self.assertTrue(catalog.uses_relay(["--profile", "chat-completions"], False))
        self.assertFalse(catalog.uses_relay(["--profile", "other"], True))

    def test_profile_forms_and_argument_boundaries(self):
        for args in (["exec", "--profile", "chat-completions"], ["--profile=chat-completions"],
                     ["-pchat-completions"], ["-p", "other", "-p", "chat-completions"]):
            self.assertEqual(catalog.selected_profile(args), "chat-completions")
        self.assertIsNone(catalog.selected_profile(["exec", "--", "--profile", "chat-completions"]))
        self.assertIsNone(catalog.selected_profile(["-c", "--profile=chat-completions"]))


if __name__ == "__main__":
    unittest.main()
