"""Exercise the packaged CLIProxyAPI against a local upstream; no inference cost."""

import http.server
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request


HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("catalog", HERE / "refresh-relay-catalog.py")
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)
PATCH = "*** Begin Patch\n*** Add File: test.txt\n+hello\n*** End Patch"
TOOL = {"type": "custom", "name": "apply_patch", "format": {"type": "text"}}


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.seen.append((self.path, self.headers.get("Authorization"), body))
        self.server.request_ids.append(self.headers.get("X-Request-Id"))
        if self.path.endswith("/chat/completions"):
            arguments = json.dumps({"input": PATCH})
            chunks = [
                {"delta": {"role": "assistant", "tool_calls": [{"index": 0, "id": "call_patch", "type": "function", "function": {"name": "apply_patch", "arguments": arguments[:12]}}]}, "finish_reason": None},
                {"delta": {"tool_calls": [{"index": 0, "function": {"arguments": arguments[12:]}}]}, "finish_reason": None},
                {"delta": {}, "finish_reason": "tool_calls"},
            ]
            events = [{"id": "chat_mock", "object": "chat.completion.chunk", "created": 1, "model": body["model"], "choices": [{"index": 0, **chunk}]} for chunk in chunks]
            payload = "".join("data: " + json.dumps(event) + "\n\n" for event in events) + "data: [DONE]\n\n"
        else:
            item = {"id": "ctc_patch", "type": "custom_tool_call", "call_id": "call_patch", "name": "apply_patch", "input": PATCH, "status": "completed"}
            response = {"id": "resp_mock", "object": "response", "created_at": 1, "model": body["model"], "status": "completed", "output": [item], "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
            events = [
                {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
                {"type": "response.output_item.added", "output_index": 0, "item": {**item, "status": "in_progress", "input": ""}},
                {"type": "response.custom_tool_call_input.delta", "item_id": "ctc_patch", "output_index": 0, "delta": PATCH},
                {"type": "response.custom_tool_call_input.done", "item_id": "ctc_patch", "output_index": 0, "input": PATCH},
                {"type": "response.output_item.done", "output_index": 0, "item": item},
                {"type": "response.completed", "response": response},
            ]
            payload = "".join("data: " + json.dumps(event) + "\n\n" for event in events)
        encoded = payload.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


@unittest.skipUnless(os.environ.get("CODEX_CLIPROXY_TEST_PROGRAM"), "set CODEX_CLIPROXY_TEST_PROGRAM to the packaged CLIProxyAPI")
class SelectiveAdapterTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.upstream.seen = []
        self.upstream.request_ids = []
        self.addCleanup(self.upstream.server_close)
        self.addCleanup(self.upstream.shutdown)
        threading.Thread(target=self.upstream.serve_forever, daemon=True).start()
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        self.url = f"http://127.0.0.1:{port}/v1"
        native = {"name": "azure/gpt-6.1-sol", "alias": "gpt-6.1-sol", "thinking": {"levels": ["low", "medium", "high", "xhigh"]}}
        chat = {"name": "azure/DeepSeek-V4.1-Flash", "alias": "DeepSeek-V4.1-Flash", "thinking": {"levels": ["none", "high"]}}
        self.routes = [native, chat]
        group = {"base-url": f"http://127.0.0.1:{self.upstream.server_port}/gateway/v1", "keys": [{}], "headers": {"X-Request-Id": "configured-id"}}
        settings = {
            "config-version": 8, "server": {"host": "127.0.0.1", "port": port},
            "management": {"disable-control-panel": True, "disable-auto-update-panel": True},
            "client": {"codex": {"enable-apply-patch": True}},
            "multimedia": {"disable-image-generation": "passthrough"},
            "routing": {"retry": {"request-retry": 0}},
            "api-keys": {
                "codex": [{**group, "name": "native", "models": [native]}],
                "openai-compatibility": [{**group, "name": "bridge", "models": [chat]}],
            },
        }
        template = self.root / "template.json"
        template.write_text(json.dumps(settings))
        self.key = self.root / "key"
        self.key.write_text("mock-upstream-secret\n")
        log = self.root.joinpath("server.log").open("w+")
        self.addCleanup(log.close)
        self.process = subprocess.Popen([sys.executable, str(HERE / "start-cliproxyapi.py"), "--program", os.environ["CODEX_CLIPROXY_TEST_PROGRAM"], "--template", str(template), "--api-key-file", str(self.key)], env={**os.environ, "XDG_RUNTIME_DIR": str(self.root)}, stdout=log, stderr=log)
        self.addCleanup(self.stop)
        for _ in range(100):
            if self.process.poll() is not None:
                log.seek(0)
                self.fail("adapter exited: " + log.read())
            try:
                request = urllib.request.Request(self.url + "/models?client_version=0.166.0", headers={"User-Agent": "codex_cli_rs/0.166.0"})
                with urllib.request.urlopen(request, timeout=1) as response:
                    self.models = json.load(response)["models"]
                break
            except OSError:
                time.sleep(0.1)
        else:
            self.fail("adapter did not start")

    def stop(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            self.process.wait(timeout=10)

    def request(self, model, **extra):
        body = {"model": model, "input": "Make the patch", "tools": [TOOL], "stream": True, "store": False, **extra}
        request = urllib.request.Request(self.url + "/responses", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=10) as response:
            return [json.loads(line[6:]) for raw in response if (line := raw.decode().strip()).startswith("data: ") and line != "data: [DONE]"]

    def test_native_tools_and_effort_are_preserved(self):
        events = self.request("gpt-6.1-sol", reasoning={"effort": "xhigh"})
        path, auth, body = self.upstream.seen[-1]
        self.assertEqual(path, "/gateway/v1/responses")
        self.assertEqual(auth, "Bearer mock-upstream-secret")
        self.assertEqual(body["model"], "azure/gpt-6.1-sol")
        self.assertEqual(body["tools"][0]["type"], "custom")
        self.assertEqual(body["reasoning"]["effort"], "xhigh")
        if expected_id := os.environ.get("CODEX_CLIPROXY_TEST_REQUEST_ID"):
            self.assertEqual(self.upstream.request_ids[-1], expected_id)
        self.assertEqual(next(e for e in events if e["type"] == "response.completed")["response"]["output"][0]["input"], PATCH)

    def test_bridge_restores_streamed_custom_tools_and_replays_history(self):
        events = self.request("DeepSeek-V4.1-Flash", reasoning={"effort": "high"}, parallel_tool_calls=True)
        path, auth, body = self.upstream.seen[-1]
        self.assertEqual(path, "/gateway/v1/chat/completions")
        self.assertEqual(auth, "Bearer mock-upstream-secret")
        self.assertEqual(body["model"], "azure/DeepSeek-V4.1-Flash")
        self.assertEqual(body["reasoning_effort"], "high")
        self.assertTrue(body["parallel_tool_calls"])
        self.assertEqual(body["tools"][0]["type"], "function")
        self.assertEqual(body["tools"][0]["function"]["parameters"]["required"], ["input"])
        item = next(e for e in events if e["type"] == "response.output_item.done")["item"]
        self.assertEqual(item["type"], "custom_tool_call")
        self.assertEqual(item["input"], PATCH)
        self.assertEqual("".join(e["delta"] for e in events if e["type"] == "response.custom_tool_call_input.delta"), PATCH)
        self.request("DeepSeek-V4.1-Flash", input=[{"role": "user", "content": "Make the patch"}, item, {"type": "custom_tool_call_output", "call_id": item["call_id"], "output": "Applied"}])
        messages = self.upstream.seen[-1][2]["messages"]
        call = next(m for m in messages if m.get("tool_calls"))["tool_calls"][0]
        self.assertEqual(json.loads(call["function"]["arguments"]), {"input": PATCH})
        self.assertEqual(next(m for m in messages if m.get("role") == "tool")["content"], "Applied")
        if expected_id := os.environ.get("CODEX_CLIPROXY_TEST_REQUEST_ID"):
            self.assertEqual(self.upstream.request_ids, [expected_id, expected_id])

    def test_private_runtime_config_is_removed_on_stop(self):
        rendered = list(self.root.glob("codex-cliproxyapi-*/config.json"))
        self.assertEqual(len(rendered), 1)
        self.assertEqual(rendered[0].stat().st_mode & 0o777, 0o600)
        self.assertIn("mock-upstream-secret", rendered[0].read_text())
        self.assertNotIn("mock-upstream-secret", (self.root / "template.json").read_text())
        self.stop()
        self.assertFalse(rendered[0].exists())

    @unittest.skipUnless(os.environ.get("CODEX_RELAY_TEST_CODEX"), "set CODEX_RELAY_TEST_CODEX to validate the generated catalog")
    def test_real_codex_loads_only_configured_models(self):
        cache = self.root / "cache" / "models.json"
        settings = {"backend": "cliproxyapi", "upstream": self.url, "client_version": "0.166.0", "routes": self.routes, "api_key_file": str(self.key), "codex": os.environ["CODEX_RELAY_TEST_CODEX"], "cache_file": str(cache), "overrides": {"DeepSeek-V4.1-Flash": {"context_window": 131072}}, "refresh_interval": 86400}
        self.assertTrue(catalog.refresh(settings))
        models = json.loads(cache.read_text())["models"]
        self.assertEqual({m["slug"] for m in models}, {"gpt-6.1-sol", "DeepSeek-V4.1-Flash"})
        native = next(m for m in models if m["slug"] == "gpt-6.1-sol")
        self.assertEqual([level["effort"] for level in native["supported_reasoning_levels"]], ["low", "medium", "high", "xhigh"])
        self.assertTrue(all(m["apply_patch_tool_type"] == "freeform" for m in models))
        self.assertEqual(next(m for m in models if m["slug"] == "DeepSeek-V4.1-Flash")["context_window"], 131072)
        before = cache.read_bytes()
        # A rebuild can change routes before the running adapter has restarted.
        settings["routes"][0]["thinking"]["levels"] = ["xhigh"]
        self.assertFalse(catalog.refresh(settings, force=True))
        self.assertEqual(cache.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
