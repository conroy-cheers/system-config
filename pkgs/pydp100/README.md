# DP100 helpers

- `dp100-powerread` reports settings and measurements.
- `dp100-powerup [-c|--config PATH]` loads `vout` and `iout`, then enables output.
  Config search order: explicit path, `./config.txt`,
  `$XDG_CONFIG_HOME/pydp100/config.txt`, `~/.config/pydp100/config.txt`.
- `dp100-poweroff` disables output, preserving the supply's setpoints.

Both switching commands preserve protection thresholds and verify settings and
measured voltage. Verification requires two consecutive samples: at or below
0.5 V for OFF, or within 5% (at least 0.1 V tolerance) of the setpoint for ON.
Verification times out after five seconds of polling. Failure exits nonzero,
including when a current-limited load prevents reaching the ON voltage.

Config values use volts and amps, with optional `V` / `A` suffixes and `#`
comments. See `config.txt`, also installed at `$out/share/pydp100/config.txt`,
for an example. The installed example is not an automatic fallback.

Set `DP100_SERIAL` to select a supply when more than one is attached.
`DP100_TRACE=PATH` enables timestamped JSONL traffic and verification logs.
A per-user process lock serializes the helpers' query/write/verify cycles.

All commands use `dp100.py`; Nix supplies the Python dependencies and generates
the launchers. The protocol is based on
[palzhj/pydp100](https://github.com/palzhj/pydp100/tree/116d10c0e5b34a80c4dfd9087f1b10544a89cab8).
The local transport checks opcode, sequence, length and CRC, consumes write
acknowledgements, and never retries an output-setting write.

On firmware 1.5, each HID write releases the preceding response. Read-only
marker queries collect these delayed replies. Every report is paced 100 ms
apart: faster follow-up queries can leave physical output on despite settings
reporting OFF. These hardware workarounds and measured-voltage verification
must be preserved when changing the transport.

From the repository root, `nix build path:.#pydp100` builds the package and runs
`test_dp100.py` without hardware. Tests use a simulated clock and supply to
cover delayed/stale replies, rejected or unapplied writes, pacing, voltage
verification, preserved limits, and config handling.
