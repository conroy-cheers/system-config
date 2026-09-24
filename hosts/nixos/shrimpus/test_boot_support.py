"""Exercise boot scripts against temporary sysfs/proc fixtures and fake services."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

HERE = Path(__file__).parent


class BootSupportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}")
        self.write("run/shrimpus-wifi-health/.keep", "")
        self.write("sys/bus/platform/devices/unisoc_wifi/.keep", "")
        self.write("sys/bus/platform/drivers_probe", "")
        self.command("systemctl", f'echo "$*" >> "{self.root}/calls"\necho "$*"')

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def command(self, name, body):
        path = self.write(f"bin/{name}", "#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def script(self, name):
        script = (HERE / name).read_text()
        script = re.sub(r"(?<![\w/])(/sys/|/proc/|/run/shrimpus-|/boot/firmware)",
                        lambda match: str(self.root) + match[0], script)
        return subprocess.run(["bash", "-c", script], env=self.env, capture_output=True)

    def test_reprobe_is_bounded(self):
        for _ in range(2):
            result = self.script("wifi-health.sh")
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"interface still missing", result.stdout)
        result = self.script("wifi-health.sh")
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"interface still missing", result.stdout)
        probe = self.root / "sys/bus/platform/drivers_probe"
        self.assertEqual(probe.read_text(), "unisoc_wifi\n")
        self.assertEqual(
            (self.root / "calls").read_text(),
            "stop shrimpus-wifi-health.timer\n",
        )
        probe.write_text("unchanged")
        self.assertEqual(self.script("wifi-health.sh").returncode, 0)
        self.assertEqual(probe.read_text(), "unchanged")
        self.assertEqual(
            (self.root / "calls").read_text(),
            "stop shrimpus-wifi-health.timer\nstop shrimpus-wifi-health.timer\n",
        )

    def test_bound_device_is_not_reprobed(self):
        (self.root / "sys/bus/platform/devices/unisoc_wifi/driver").symlink_to("/fake-driver")
        self.assertEqual(self.script("wifi-health.sh").returncode, 1)
        self.assertEqual((self.root / "sys/bus/platform/drivers_probe").read_text(), "")

    def test_late_interface_starts_services_even_after_retry_limit(self):
        self.write("run/shrimpus-wifi-health/attempts", "3\n")
        self.write("sys/class/net/wlan0/.keep", "")
        self.assertEqual(self.script("wifi-health.sh").returncode, 0)
        self.assertIn("start --no-block wpa_supplicant-wlan0.service dhcpcd.service",
                      (self.root / "calls").read_text())
        self.assertIn("stop shrimpus-wifi-health.timer",
                      (self.root / "calls").read_text())

    def test_snapshots_rotate_and_stop_after_fifteen_minutes(self):
        self.write("proc/uptime", "60.00 0.00\n")
        self.write("proc/meminfo", "MemTotal: 2000000 kB\n")
        boot_id = self.write("proc/sys/kernel/random/boot_id", "first-boot\n")
        self.command("mountpoint", "exit 0")
        self.command("sync", "exit 0")
        self.command("ip", "echo 'wlan0 UP 192.0.2.1/24'")
        self.command("journalctl", "echo 'first boot log'")
        result = self.script("boot-diagnostics.sh")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        base = self.root / "boot/firmware/SHRIMPUS"
        self.assertIn("192.0.2.1", (base / "current/status.txt").read_text())
        boot_id.write_text("second-boot\n")
        self.command("journalctl", "echo 'second boot log'")
        self.assertEqual(self.script("boot-diagnostics.sh").returncode, 0)
        self.assertEqual((base / "previous/kernel.txt").read_text(), "first boot log\n")
        self.assertEqual((base / "current/kernel.txt").read_text(), "second boot log\n")
        self.write("proc/uptime", "901.00 0.00\n")
        self.command("journalctl", "echo 'must not be written'")
        self.assertEqual(self.script("boot-diagnostics.sh").returncode, 0)
        self.assertEqual((base / "current/kernel.txt").read_text(), "second boot log\n")


if __name__ == "__main__":
    unittest.main()
