"""Integration tests; run with Python, e2fsprogs, OpenSSH and zstd on PATH."""

import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("personalize.py")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


class PersonalizationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sd image test ")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.key = self.work / "host key"
        run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.key))
        self.public = run("ssh-keygen", "-y", "-f", str(self.key)).decode().strip()
        self.root = self.work / "root.img"
        with self.root.open("wb") as stream:
            stream.truncate(16 * 1024 * 1024)
        run("mke2fs", "-q", "-F", "-t", "ext4", "-L", "NIXOS_SD", str(self.root))
        self.image = self.work / "input.img"
        self.output = self.work / "output.img"
        self.assemble()

    def assemble(self):
        prefix = bytearray(1024 * 1024)
        prefix[510:512] = b"\x55\xaa"
        prefix[450] = 0x83
        struct.pack_into("<II", prefix, 454, 2048, self.root.stat().st_size // 512)
        self.image.write_bytes(prefix + self.root.read_bytes())

    def invoke(self, *extra, expected=None):
        return subprocess.run([
            sys.executable, str(SCRIPT), "--image", str(self.image),
            "--host-privkey", str(self.key), "--expected-host-pubkey",
            expected or self.public, "--output", str(self.output), *extra,
        ], capture_output=True)

    def test_round_trip_and_source_unchanged(self):
        original = hashlib.sha256(self.image.read_bytes()).digest()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(hashlib.sha256(self.image.read_bytes()).digest(), original)
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)
        raw = self.output.read_bytes()
        self.assertEqual(raw[:1024 * 1024], self.image.read_bytes()[:1024 * 1024])
        self.root.write_bytes(raw[1024 * 1024:])
        private = run("debugfs", "-R", "cat /etc/ssh/ssh_host_ed25519_key", str(self.root))
        self.assertEqual(private, self.key.read_bytes())
        info = run("debugfs", "-R", "stat /etc/ssh/ssh_host_ed25519_key", str(self.root))
        self.assertIn(b"Mode:  0600", info)
        run("e2fsck", "-f", "-n", str(self.root))
        self.assertNotIn(private, result.stdout + result.stderr)

    def test_compressed_input(self):
        compressed = self.image.with_suffix(".img.zst")
        run("zstd", "-q", str(self.image), "-o", str(compressed))
        self.image = compressed
        self.assertEqual(self.invoke().returncode, 0)

    def test_wrong_key_leaves_no_output(self):
        self.assertNotEqual(self.invoke(expected="ssh-ed25519 WRONG").returncode, 0)
        self.assertFalse(self.output.exists())

    def test_existing_output_and_force(self):
        self.output.write_bytes(b"keep me")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"keep me")
        self.assertEqual(self.invoke("--force").returncode, 0)

    def test_failed_force_preserves_existing_output(self):
        self.output.write_bytes(b"keep me")
        self.image.write_bytes(b"bad image")
        self.assertNotEqual(self.invoke("--force").returncode, 0)
        self.assertEqual(self.output.read_bytes(), b"keep me")
        self.assertFalse(list(self.work.glob(".personalize-*")))

    def test_refuse_symlink_parent(self):
        run("debugfs", "-w", "-R", "symlink /etc /elsewhere", str(self.root))
        self.assemble()
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_refuse_wrong_root_label(self):
        run("tune2fs", "-L", "OTHER", str(self.root))
        self.assemble()
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
