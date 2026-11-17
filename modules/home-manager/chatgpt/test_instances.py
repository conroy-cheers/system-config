"""Check the generated instance homes with the real Codex CLI, without inference."""

import json
import os
from pathlib import Path
import select
import subprocess
import unittest


class InstanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ["CODEX_INSTANCE_TEST_ROOT"])
        cls.workspace = cls.root / "workspace"
        cls.workspace.mkdir()
        # Rebase the fixture's absolute paths into the build sandbox.
        for directory in (".codex", ".codex-work"):
            config = cls.root / directory / "config.toml"
            config.write_text(config.read_text().replace("/chatgpt-test-home", str(cls.root)))

    def codex(self, directory, *arguments):
        result = subprocess.run(
            [os.environ["CODEX_PROFILE_TEST_CODEX"], *arguments],
            env=os.environ | {"CODEX_HOME": str(self.root / directory), "OPENAI_API_KEY": "fixture-key"},
            cwd=self.workspace, text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_each_instance_loads_its_own_context_and_override(self):
        for directory, context, override, other in (
            (".codex", "Default global instructions", "Default override instructions", "Work override instructions"),
            (".codex-work", "Use the work instance's global instructions.", "Work override instructions", "Default override instructions"),
        ):
            with self.subTest(instance=directory):
                arguments = ("-c", 'model="gpt-6.1-sol"', "-c", 'model_provider="openai"',
                             "debug", "prompt-input", "Check instance context")
                prompt = json.dumps(self.codex(directory, *arguments))
                self.assertIn(override, prompt)
                self.assertNotIn(context, prompt)
                self.assertNotIn(other, prompt)
                path = self.root / directory / "AGENTS.override.md"
                hidden = path.with_suffix(".hidden")
                path.rename(hidden)
                try:
                    prompt = json.dumps(self.codex(directory, *arguments))
                    self.assertIn(context, prompt)
                    self.assertNotIn(override, prompt)
                    self.assertNotIn(other, prompt)
                finally:
                    hidden.rename(path)

    def test_each_instance_discovers_its_own_plugin_marketplace(self):
        for directory, version in ((".codex", "1.0.0"), (".codex-work", "2.0.0")):
            with self.subTest(instance=directory):
                plugins = self.codex(directory, "plugin", "list", "--json", "--marketplace", "home-manager")
                serialized = json.dumps(plugins)
                self.assertIn("fixture-plugin", serialized)
                self.assertIn(version, serialized)
                other_version = "2.0.0" if version == "1.0.0" else "1.0.0"
                self.assertNotIn(other_version, serialized)

    def test_each_instance_discovers_its_own_skills(self):
        for directory, skill_directory in ((".codex", "fixture-skill"), (".codex-work", "fixture-skill.md")):
            with self.subTest(instance=directory):
                server = subprocess.Popen(
                    [os.environ["CODEX_PROFILE_TEST_CODEX"], "app-server", "--listen", "stdio://"],
                    env=os.environ | {"CODEX_HOME": str(self.root / directory)},
                    cwd=self.workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
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
                                return response["result"]

                    rpc(1, "initialize", {"clientInfo": {"name": "instance-test", "version": "1"}})
                    server.stdin.write(b'{"method":"initialized"}\n')
                    server.stdin.flush()
                    data = rpc(2, "skills/list", {"cwds": [str(self.workspace)], "forceReload": True})["data"]
                    paths = {skill["path"] for entry in data for skill in entry["skills"]}
                    expected = str(self.root / directory / "skills" / skill_directory / "SKILL.md")
                    self.assertIn(expected, paths)
                    self.assertEqual([error for entry in data for error in entry["errors"]], [])
                finally:
                    server.terminate()
                    server.wait(timeout=5)
                    server.stdin.close()
                    server.stdout.close()


if __name__ == "__main__":
    unittest.main()
