"""Regression coverage for mutable Codex configuration profile files."""

import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import tomllib
import unittest


MERGER = os.environ.get("CODEX_PROFILE_TEST_MERGER")


@unittest.skipUnless(MERGER, "run the tests.nix derivation for the Home Manager merger")
class MutableProfileTests(unittest.TestCase):
    def merge(self, source, target, *, dry_run=False, check=True):
        script = Path(MERGER).read_text().replace("/CODEX_TEST_SOURCE", str(source)).replace("/CODEX_TEST_TARGET", str(target))
        environment = os.environ.copy()
        environment.pop("DRY_RUN", None)
        if dry_run:
            environment["DRY_RUN"] = "1"
        return subprocess.run(["bash", "-euc", 'errorEcho() { echo "$@" >&2; };\n' + script],
                              env=environment, check=check, capture_output=True, text=True)

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
            profile.symlink_to(os.environ["CODEX_PROFILE_TEST_STORE_CONFIG"])
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

    def test_remove_obsolete_catalog_preserves_mutable_model(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "managed.toml"
            source.write_text('model_provider = "relay"\n')
            target = root / "chat-completions.config.toml"
            target.write_text('# My choice\nmodel = "chosen-model"\nmodel_catalog_json = "/old/catalog.json"\n')
            self.merge(source, target)
            settings = tomllib.loads(target.read_text())
            self.assertEqual(settings["model"], "chosen-model")
            self.assertNotIn("model_catalog_json", settings)

    def test_malformed_config_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "managed.toml"
            source.write_text('model_provider = "relay"\n')
            target = Path(temporary) / "config.toml"
            target.write_text('model = [broken\n')
            result = self.merge(source, target, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), 'model = [broken\n')

    def test_store_symlink_migration_and_dry_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "managed.toml"
            source.write_text('model_provider = "relay"\n')
            target = Path(temporary) / "config.toml"
            store_config = Path(os.environ["CODEX_PROFILE_TEST_STORE_CONFIG"])
            original = store_config.read_text()
            target.symlink_to(store_config)
            self.merge(source, target, dry_run=True)
            self.assertTrue(target.is_symlink())
            self.merge(source, target)
            self.assertFalse(target.is_symlink())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(store_config.read_text(), original)

    def test_runtime_symlink_and_permissions_are_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "managed.toml"
            source.write_text('model_provider = "relay"\n')
            destination = root / "actual.toml"
            destination.write_text('model = "chosen-model"\n')
            destination.chmod(0o640)
            target = root / "config.toml"
            target.symlink_to(destination)
            self.merge(source, target)
            self.assertTrue(target.is_symlink())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o640)
            self.assertEqual(tomllib.loads(destination.read_text())["model"], "chosen-model")

    def test_mcp_transport_changes_remove_incompatible_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "managed.toml"
            target = root / "config.toml"
            target.write_text('[mcp_servers.example]\ncommand = "old-server"\nargs = ["--old"]\n')
            source.write_text('[mcp_servers.example]\nurl = "https://example.invalid/mcp"\n')
            self.merge(source, target)
            server = tomllib.loads(target.read_text())["mcp_servers"]["example"]
            self.assertEqual(server, {"url": "https://example.invalid/mcp"})
            source.write_text('[mcp_servers.example]\ncommand = "new-server"\n')
            self.merge(source, target)
            server = tomllib.loads(target.read_text())["mcp_servers"]["example"]
            self.assertEqual(server, {"command": "new-server"})


if __name__ == "__main__":
    unittest.main()
