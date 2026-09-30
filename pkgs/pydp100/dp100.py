"""DP100 helpers with bounded, correlated HID transactions.

Protocol based on palzhj/pydp100 (116d10c0e5b34a80c4dfd9087f1b10544a89cab8).
"""

import argparse
import fcntl
import json
import os
import secrets
import struct
import sys
import tempfile
import time
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import NamedTuple

import crcmod
import hid

VID, PID = 0x2E3C, 0xAF01
DEVICEINFO, BASICINFO, BASICSET = 0x10, 0x30, 0x35
crc16 = crcmod.mkCrcFun(0x18005, rev=True, initCrc=0xFFFF, xorOut=0)


class Settings(NamedTuple):
    """Active profile; voltage in mV and current in mA."""

    index: int
    enabled: int
    voltage: int
    current: int
    ovp: int
    ocp: int


class Status(NamedTuple):
    """Measurements in mV, mA and tenths of a degree Celsius."""

    input_voltage: int
    voltage: int
    current: int
    max_voltage: int
    temperature: int
    external_temperature: int
    supply_5v: int
    output_mode: int
    work_state: int


def frame(opcode, payload=b"", direction=0xFB, sequence=0):
    packet = bytes((direction, opcode, sequence, len(payload))) + payload
    return packet + struct.pack("<H", crc16(packet))


def decode(report):
    if len(report) < 6 or report[0] != 0xFA:
        return None
    end = 6 + report[3]
    if end > len(report) or crc16(report[:end]) != 0:
        return None
    return report[1], report[2], bytes(report[4 : end - 2])


class DP100:
    def __init__(self, device):
        self.device = device
        self.sequence = secrets.randbelow(256)

    def trace(self, **fields):
        filename = os.environ.get("DP100_TRACE")
        if filename:
            with open(filename, "a") as log:
                log.write(json.dumps({"time": time.time(), **fields}) + "\n")

    def read(self, timeout):
        report = self.device.read(64, timeout=timeout)
        if report:
            self.trace(rx=bytes(report).hex())
        return report

    def drain(self):
        # Old versions exit without reading write ACKs, leaving them for the
        # next process. Bound this even if another source keeps sending data.
        for _ in range(64):
            if not self.read(10):
                return
        raise RuntimeError("DP100 input queue did not become idle")

    def request(self, opcode, payload=b"", *, response_size, timeout=1.0):
        self.drain()
        # Some DP100 firmware releases the previous response on the next
        # request. A different, read-only opcode both establishes a boundary
        # and clocks out delayed replies. Never resend an output mutation.
        marker = BASICINFO if opcode == DEVICEINFO else DEVICEINFO
        marker_size = 16 if marker == BASICINFO else 40
        sequence = self.write(marker)
        self.receive(marker, marker_size, marker, timeout, sequence)
        sequence = self.write(opcode, payload)
        return self.receive(opcode, response_size, marker, timeout, sequence)

    def write(self, opcode, payload=b""):
        # hidapi requires a zero report ID for devices with unnumbered reports.
        self.sequence = (self.sequence + 1) & 0xFF
        packet = b"\x00" + frame(opcode, payload, sequence=self.sequence).ljust(
            64, b"\x00"
        )
        self.trace(tx=packet.hex())
        if self.device.write(packet) != len(packet):
            raise RuntimeError("Incomplete DP100 HID write")
        # The device processes reports one transaction behind. Rapid follow-up
        # queries can prevent physical output changes despite successful ACKs
        # and changed settings. Pace every report, including read-only markers.
        time.sleep(0.1)
        return self.sequence

    def receive(self, opcode, response_size, marker, timeout, sequence):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            remaining = min(100, max(1, int((deadline - time.monotonic()) * 1000)))
            parsed = decode(self.read(remaining))
            if parsed is not None:
                received_opcode, received_sequence, data = parsed
                if (
                    received_opcode == opcode
                    and received_sequence == sequence
                    and len(data) == response_size
                ):
                    return data
            self.write(marker)
        raise RuntimeError(
            f"DP100 timed out waiting for opcode 0x{opcode:02x}, "
            f"{response_size}-byte response"
        )

    def settings(self):
        data = self.request(BASICSET, b"\x80", response_size=10)
        return Settings(*struct.unpack("<BBHHHH", data))

    def status(self):
        data = self.request(BASICINFO, response_size=16)
        return Status(*struct.unpack("<7HBB", data))

    def set_output(self, enabled, voltage=None, current=None):
        settings = self.settings()
        voltage = settings.voltage if voltage is None else voltage
        current = settings.current if current is None else current
        if enabled:
            maximum = self.status().max_voltage
            if not 0 < voltage <= min(maximum, settings.ovp):
                raise RuntimeError(
                    "Requested voltage exceeds supply/protection limits or is zero"
                )
            if not 0 < current <= settings.ocp:
                raise RuntimeError(
                    "Requested current exceeds protection limit or is zero"
                )
        desired = settings._replace(
            enabled=int(enabled), voltage=voltage, current=current
        )
        payload = struct.pack("<BBHHHH", 0x20 | (settings.index & 0x0F), *desired[1:])
        ack = self.request(BASICSET, payload, response_size=1)
        if ack != b"\x01":
            raise RuntimeError(f"DP100 rejected output settings (ACK {ack.hex()})")
        # ACK alone does not prove that the requested state was applied.
        actual = self.settings()
        if actual[1:] != desired[1:]:
            raise RuntimeError(
                f"DP100 settings verification failed: wanted {desired}, got {actual}"
            )
        return actual, self.verify_voltage(enabled, voltage)

    def verify_voltage(self, enabled, voltage, timeout=5.0):
        deadline = time.monotonic() + timeout
        consecutive = 0
        while True:
            status = self.status()
            self.trace(
                verification={
                    "enabled": enabled,
                    "target_mv": voltage,
                    "measured_mv": status.voltage,
                }
            )
            matches = (
                abs(status.voltage - voltage) <= max(100, voltage * 0.05)
                if enabled
                else status.voltage <= 500
            )
            consecutive = consecutive + 1 if matches else 0
            if consecutive >= 2:
                return status
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "Output voltage verification failed: "
                    f"measured {status.voltage / 1000:.3f} V "
                    f"after requesting {'ON' if enabled else 'OFF'}"
                )
            time.sleep(0.1)


def load_config(filename=None):
    if filename is None:
        candidates = [Path("config.txt")]
        if os.environ.get("XDG_CONFIG_HOME"):
            candidates.append(
                Path(os.environ["XDG_CONFIG_HOME"]) / "pydp100/config.txt"
            )
        candidates.append(Path.home() / ".config/pydp100/config.txt")
        filename = next((path for path in candidates if path.is_file()), None)
        if filename is None:
            raise ValueError(
                "config.txt not found. "
                "Use --config or create ~/.config/pydp100/config.txt"
            )

    values = {}
    for line in Path(filename).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or key not in ("vout", "iout") or key in values:
            raise ValueError(f"Invalid or duplicate config setting: {line}")
        parts = value.split()
        if len(parts) not in (1, 2) or (
            len(parts) == 2 and parts[1] != {"vout": "V", "iout": "A"}[key]
        ):
            raise ValueError(f"Invalid config value: {line}")
        try:
            number = Decimal(parts[0]) * 1000
        except InvalidOperation:
            raise ValueError(f"Invalid config value: {line}") from None
        if (
            not number.is_finite()
            or not 0 < number <= 65535
            or number != number.to_integral_value()
        ):
            raise ValueError(
                f"Config value out of range or finer than milli-units: {line}"
            )
        values[key] = int(number)
    if values.keys() != {"vout", "iout"}:
        raise ValueError("Config must specify vout and iout")
    return values["vout"], values["iout"]


@contextmanager
def open_supply():
    # Serialize the three helpers, including the whole query/write/verify cycle.
    lock_dir = Path(tempfile.gettempdir()) / f"pydp100-{os.getuid()}"
    lock_dir.mkdir(mode=0o700, exist_ok=True)
    if lock_dir.is_symlink() or lock_dir.stat().st_uid != os.getuid():
        raise RuntimeError("Unsafe DP100 lock directory")
    with (lock_dir / "device.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another DP100 helper is running") from None
        devices = hid.enumerate(VID, PID)
        serial = os.environ.get("DP100_SERIAL")
        if serial:
            devices = [item for item in devices if item["serial_number"] == serial]
        if len(devices) != 1:
            raise RuntimeError(
                f"Expected one DP100, found {len(devices)}; select with DP100_SERIAL"
            )
        with hid.Device(path=devices[0]["path"]) as device:
            yield DP100(device)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Control and monitor a DP100 power supply"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser(
        "read", prog="dp100-powerread", description="Read settings and measurements"
    )
    actions.add_parser(
        "off", prog="dp100-poweroff", description="Disable and verify the output"
    )
    powerup = actions.add_parser(
        "up", prog="dp100-powerup", description="Configure and enable the output"
    )
    powerup.add_argument(
        "-c",
        "--config",
        type=Path,
        metavar="PATH",
        help=(
            "config file (default: ./config.txt, "
            "$XDG_CONFIG_HOME/pydp100/config.txt, then ~/.config/pydp100/config.txt)"
        ),
    )
    args = parser.parse_args(argv)
    try:
        limits = load_config(args.config) if args.action == "up" else None
        with open_supply() as supply:
            if args.action in ("off", "up"):
                state, status = (
                    supply.set_output(True, *limits)
                    if args.action == "up"
                    else supply.set_output(False)
                )
                print(
                    f"Output {'ON' if state.enabled else 'OFF'} verified; "
                    f"set {state.voltage / 1000:.3f} V, {state.current / 1000:.3f} A; "
                    f"measured {status.voltage / 1000:.3f} V, "
                    f"{status.current / 1000:.3f} A"
                )
            else:
                state = supply.settings()
                status = supply.status()
                print(
                    f"Output: {'ON' if state.enabled else 'OFF'}, "
                    f"set: {state.voltage / 1000:.3f} V / "
                    f"{state.current / 1000:.3f} A, "
                    f"Vout: {status.voltage / 1000:.3f} V, "
                    f"Iout: {status.current / 1000:.3f} A, "
                    f"temperature: {status.temperature / 10:.1f} degree, "
                    f"OVP: {state.ovp / 1000:.3f} V, OCP: {state.ocp / 1000:.3f} A"
                )
    except (OSError, RuntimeError, ValueError, hid.HIDException) as error:
        print(f"DP100: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
