import contextlib
import io
import os
import struct
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import dp100


class FakeSupply:
    """Firmware that releases each response only on the next HID write."""

    def __init__(self):
        self.pending = dp100.frame(dp100.BASICSET, b"\x01", 0xFA)
        self.reports = []
        self.settings = (0, 0, 19000, 1000, 24000, 2000)
        self.mutations = []
        self.reject = False
        self.ignore_write = False
        self.physical_state = 0
        self.queued_activation = None
        self.activation = None

    def read(self, size, timeout=None):
        return self.reports.pop(0) if self.reports else b""

    def write(self, packet):
        # The output control loop applies changes after the next report;
        # another report arriving too quickly can cancel that physical change.
        if self.activation is not None:
            due, state = self.activation
            if time.monotonic() >= due:
                self.physical_state = state
            self.activation = None
        if self.queued_activation is not None:
            self.activation = (time.monotonic() + 0.05, self.queued_activation)
            self.queued_activation = None
        assert len(packet) == 65 and packet[0] == 0
        request = packet[1:]
        opcode, length = request[1], request[3]
        payload = request[4 : 4 + length]
        if opcode == dp100.DEVICEINFO:
            data = bytes(40)
        elif opcode == dp100.BASICINFO:
            data = struct.pack(
                "<7HBB",
                20000,
                19000 if self.physical_state else 0,
                30,
                19500,
                280,
                280,
                5000,
                0,
                0,
            )
        elif opcode == dp100.BASICSET and payload == b"\x80":
            data = struct.pack("<BBHHHH", *self.settings)
        elif opcode == dp100.BASICSET and len(payload) == 10:
            self.mutations.append(payload)
            if not (self.reject or self.ignore_write):
                self.settings = (0,) + struct.unpack("<BBHHHH", payload)[1:]
                self.queued_activation = self.settings[1]
            data = b"\x00" if self.reject else b"\x01"
        else:
            raise AssertionError((opcode, payload))
        self.reports.append(self.pending)
        self.pending = dp100.frame(opcode, data, 0xFA, sequence=request[2])
        return len(packet)


class Tests(unittest.TestCase):
    def setUp(self):
        # Advance a shared clock so the fake firmware still checks pacing,
        # without making the tests wait for real device delays.
        self.now = 0.0
        self.enterContext(patch.object(time, "monotonic", side_effect=lambda: self.now))
        self.enterContext(patch.object(time, "sleep", side_effect=self.advance_time))
        self.enterContext(patch.dict(os.environ, {"DP100_TRACE": ""}))

    def advance_time(self, seconds):
        self.now += seconds

    def test_bad_reports(self):
        for packet in (b"", b"\xfa", b"\xfa\x35\0\x0a\0\0", bytes(64)):
            self.assertIsNone(dp100.decode(packet))
        good = dp100.frame(dp100.BASICSET, b"\x01", 0xFA)
        self.assertEqual(dp100.decode(good), (dp100.BASICSET, 0, b"\x01"))
        self.assertIsNone(dp100.decode(good[:-1] + bytes((good[-1] ^ 1,))))

    def test_delayed_response_and_stale_ack(self):
        fake = FakeSupply()
        fake.reports.extend([b"\xfa", bytes(64)])
        supply = dp100.DP100(fake)
        self.assertEqual(supply.settings(), fake.settings)
        self.assertEqual(supply.status().input_voltage, 20000)
        self.assertEqual(supply.settings(), fake.settings)
        self.assertFalse(fake.mutations)

    def test_switch_preserves_limits_and_sends_each_write_once(self):
        fake = FakeSupply()
        supply = dp100.DP100(fake)
        state, status = supply.set_output(True, 19000, 1000)
        self.assertEqual(state.enabled, 1)
        self.assertEqual(status.voltage, 19000)
        state, status = supply.set_output(False)
        self.assertEqual(state.enabled, 0)
        self.assertEqual(status.voltage, 0)
        self.assertEqual(fake.settings, (0, 0, 19000, 1000, 24000, 2000))
        self.assertEqual(len(fake.mutations), 2)
        self.assertEqual(fake.physical_state, 0)

    def test_settings_off_is_not_proof_of_physical_poweroff(self):
        fake = FakeSupply()
        fake.physical_state = 1
        with self.assertRaisesRegex(RuntimeError, "voltage verification failed"):
            dp100.DP100(fake).verify_voltage(False, 19000, timeout=0)

    def test_same_opcode_wrong_sequence_is_ignored(self):
        fake = FakeSupply()
        supply = dp100.DP100(fake)
        fake.reports = [
            dp100.frame(dp100.BASICSET, b"\x00", 0xFA, sequence=6),
            dp100.frame(dp100.BASICSET, b"\x01", 0xFA, sequence=7),
        ]
        self.assertEqual(
            supply.receive(dp100.BASICSET, 1, dp100.DEVICEINFO, 1, 7), b"\x01"
        )

    def test_rejected_and_unapplied_writes_fail(self):
        for attribute, expected in (
            ("reject", "rejected"),
            ("ignore_write", "verification failed"),
        ):
            fake = FakeSupply()
            setattr(fake, attribute, True)
            with self.assertRaisesRegex(RuntimeError, expected):
                dp100.DP100(fake).set_output(True, 19000, 1000)
            self.assertEqual(len(fake.mutations), 1)

    def test_out_of_range_does_not_write(self):
        fake = FakeSupply()
        with self.assertRaisesRegex(RuntimeError, "exceeds"):
            dp100.DP100(fake).set_output(True, 22000, 1000)
        self.assertFalse(fake.mutations)

    def test_missing_responses_time_out_without_mutating(self):
        fake = FakeSupply()
        fake.read = lambda size, timeout=None: b""
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            dp100.DP100(fake).request(
                dp100.BASICSET, b"\x80", response_size=10, timeout=0.01
            )
        self.assertFalse(fake.mutations)

    def test_config(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.txt"
            config.write_text("# supply\n\nvout = 19.0 V\niout = 1.0 A\n")
            self.assertEqual(dp100.load_config(config), (19000, 1000))
            for text in (
                "vout = -19 V\niout = 1 A",
                "vout = nan V\niout = 1 A",
                "vout = sNaN V\niout = 1 A",
                "vout = invalid V\niout = 1 A",
                "vout = 19.0001 V\niout = 1 A",
                "vout = 19 A\niout = 1 A",
                "vout = 19 V\nvout = 20 V\niout = 1 A",
                "vout = 19 V",
            ):
                with self.subTest(text=text):
                    config.write_text(text)
                    with self.assertRaises(ValueError):
                        dp100.load_config(config)

    def test_config_search_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.enterContext(contextlib.chdir(root))
            self.enterContext(
                patch.dict(
                    os.environ,
                    {
                        "HOME": str(root / "home"),
                        "XDG_CONFIG_HOME": str(root / "xdg"),
                    },
                )
            )
            paths = [
                root / "explicit.txt",
                root / "config.txt",
                root / "xdg/pydp100/config.txt",
                root / "home/.config/pydp100/config.txt",
            ]
            for voltage, path in enumerate(paths, start=1):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"vout = {voltage} V\niout = 1 A\n")
            self.assertEqual(dp100.load_config(paths[0]), (1000, 1000))
            paths[0].unlink()
            with self.assertRaises(FileNotFoundError):
                dp100.load_config(paths[0])
            for voltage, path in enumerate(paths[1:], start=2):
                self.assertEqual(dp100.load_config(), (voltage * 1000, 1000))
                path.unlink()
            with self.assertRaisesRegex(ValueError, "config.txt not found"):
                dp100.load_config()

    def test_invalid_config_fails_before_opening_device(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "invalid.txt"
            config.write_text("vout = invalid V\niout = 1 A\n")
            with patch.object(dp100, "open_supply") as open_supply:
                with contextlib.redirect_stderr(io.StringIO()) as errors:
                    self.assertEqual(dp100.main(["up", "-c", str(config)]), 1)
                self.assertIn("Invalid config value", errors.getvalue())
                open_supply.assert_not_called()

    def test_read_and_off_do_not_load_config(self):
        fake = FakeSupply()
        fake.physical_state = 1
        fake.settings = (0, 1, 19000, 1000, 24000, 2000)
        with patch.object(dp100, "load_config") as load_config:
            with patch.object(dp100, "open_supply") as open_supply:
                open_supply.return_value.__enter__.return_value = dp100.DP100(fake)
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(dp100.main(["read"]), 0)
                    self.assertFalse(fake.mutations)
                    self.assertEqual(dp100.main(["off"]), 0)
                self.assertIn("Output: ON", output.getvalue())
                self.assertIn("Output OFF verified", output.getvalue())
                load_config.assert_not_called()


if __name__ == "__main__":
    unittest.main()
