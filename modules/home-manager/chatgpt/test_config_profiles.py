"""Regression coverage for mutable Codex configuration profile files."""

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import tomllib
import unittest


MERGER = Path(__file__).with_name("merge-config.py")


class MutableProfileTests(unittest.TestCase):
    def merge(self, source, target, remove=None):
        subprocess.run([sys.executable, str(MERGER), str(source), str(target),
                        json.dumps(remove or [])], check=True)

    @unittest.skipUnless(os.environ.get("CODEX_PROFILE_TEST_CODEX"), "set CODEX_PROFILE_TEST_CODEX to the unwrapped binary")
    def test_migrate_symlink_save_model_and_merge_again(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "managed.toml"
            source.write_text('model_provider = "relay"\nweb_search = "disabled"\n'
                              '[model_providers.relay]\nname = "Test relay"\nwire_api = "responses"\n')
            source.chmod(0o444)
            home = root / "codex-home"
            home.mkdir()
            profile = home / "chat-completions.config.toml"
            profile.symlink_to(source)
            self.merge(source, profile)
            self.assertFalse(profile.is_symlink())
            self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
            # A standalone app-server only accepts writes to its active user
            # config. Point that at the migrated profile, matching the TUI's
            # selected-profile config target without starting an inference turn.
            (home / "config.toml").symlink_to(profile)

            server = subprocess.Popen(
                [os.environ["CODEX_PROFILE_TEST_CODEX"], "app-server", "--listen", "stdio://"],
                env=os.environ | {"CODEX_HOME": str(home)}, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            try:
                def rpc(identifier, method, params):
                    server.stdin.write((json.dumps({"id": identifier, "method": method, "params": params}) + "\n").encode())
                    server.stdin.flush()
                    while True:
                        self.assertTrue(select.select([server.stdout], [], [], 15)[0], "app-server request timed out")
                        line = server.stdout.readline()
                        self.assertTrue(line, "app-server exited before responding")
                        response = json.loads(line)
                        if response.get("id") == identifier:
                            self.assertNotIn("error", response, response)
                            return response

                rpc(1, "initialize", {"clientInfo": {"name": "profile-test", "version": "1"}})
                server.stdin.write(b'{"method":"initialized"}\n')
                server.stdin.flush()
                rpc(2, "config/batchWrite", {
                    "filePath": str(profile.resolve()),
                    "edits": [{"keyPath": "model", "value": "DeepSeek-V4.1-Flash", "mergeStrategy": "replace"}],
                })
            finally:
                server.terminate()
                server.wait(timeout=5)
                server.stdin.close()
                server.stdout.close()

            self.merge(source, profile)
            settings = tomllib.loads(profile.read_text())
            self.assertEqual(settings["model"], "DeepSeek-V4.1-Flash")
            self.assertEqual(settings["model_provider"], "relay")
            self.assertNotIn("model =", source.read_text())

    def test_remove_obsolete_catalog_preserves_mutable_model_and_comments(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "managed.toml"
            source.write_text('model_provider = "relay"\n')
            target = root / "chat-completions.config.toml"
            target.write_text('# My choice\nmodel = "chosen-model"\nmodel_catalog_json = "/old/catalog.json"\n')
            self.merge(source, target, [["model_catalog_json"]])
            settings = tomllib.loads(target.read_text())
            self.assertEqual(settings["model"], "chosen-model")
            self.assertNotIn("model_catalog_json", settings)
            self.assertIn("# My choice", target.read_text())


if __name__ == "__main__":
    unittest.main()
