# Nightingale on sleet

Nightingale is configured in `hosts/nixos/sleet/nightingale.nix`. The shared
service catalogue renders its authenticated HTTPS ingress on snow at
`https://nightingale.corncheese.org`, plus a Media homepage entry. Ensure DNS for
that name reaches snow's existing ingress before use. The existing certificate
resolver and Authelia forward-auth flow handle TLS/login; phones also need to
log in.

## Playback, microphones and phone controls

The full self-hosted browser app captures microphones on the device running
that app. Use the trusted HTTPS URL and grant microphone permission there for
scoring. Sleet serves the app and analyzes music; it need not have a microphone
attached. See [upstream self-hosted microphone guidance](https://nightingale.cafe/docs/self-hosted/#microphone-support-and-https).

The QR guest page is a separate remote-control interface: guests manage the
queue and control playback on the host player. It does **not** capture the
guest phone's microphone or play audio on the guest device. Its microphone
selector controls inputs already exposed by the host player. Opening the full
app on a phone is a different flow, not a wireless microphone for another
player. See [upstream phone queue documentation](https://nightingale.cafe/docs/queue-from-phone/).

## Runtime and data

- Upstream CPU image **1.4.1**, pinned by multi-platform digest, runs as the
  image's non-root user. No GPU device access is granted. Sleet's Tesla P100
  compatibility with upstream's downloaded PyTorch/CUDA stack is not assumed.
- Port **8783** uses the existing topology's listener/firewall policy. Only the
  ingress host is granted firewall access, not the whole LAN. Host networking
  avoids publishing a container NAT port that might bypass host firewall rules.
- `NIGHTINGALE_LIBRARY_PATH=""` overrides the image's default folder pin, keeping
  Plex/Jellyfin/Navidrome source selection available. Connect the desired source
  in the sidebar after setup. No existing Plex credentials are copied into the
  container or this repository. Verify that its PMS address is reachable.
- OPS/RED music remains mounted read-only under `/songs`. To choose local music
  declaratively instead, set `NIGHTINGALE_LIBRARY_PATH="/songs"`; this hides the
  source selectors again. See [upstream library configuration](https://nightingale.cafe/docs/docker/#configuring-the-music-library).
- `nightingale-data` is a named OCI volume mounted at `/data`; image ownership is
  retained rather than guessing an upstream UID. Its contents include settings,
  analysis results, downloaded tools and models. In particular, `/data/vendor`
  contains the bootstrapped toolchain; preserve it across container recreation.
  With `HOME=/data`, download caches persist too. Sleet already persists
  `/var/lib`, including Podman/Docker storage. Do not delete the volume to update.
- First startup/first analysis downloads Python, ffmpeg, ML dependencies and
  models. Allow several GB of disk and a potentially long CPU analysis warm-up.
  The container digest pins the app, not these runtime bootstrap downloads.
- Systemd waits for the state/media mount paths. Music files must be readable
  by the container's non-root user. No write permission to the music is needed.

## Validate and deploy

From the repository's development shell, with the private corncheese-server
input available:

```sh
nix fmt
nix eval .#nixosConfigurations.sleet.config.system.build.toplevel.drvPath --show-trace
nix eval .#nixosConfigurations.snow.config.system.build.toplevel.drvPath --show-trace
nix build .#nixosConfigurations.sleet.config.system.build.toplevel
```

Deploy **both** sleet (runtime and restricted firewall rule) and snow (route,
Authelia access rule and homepage) through the repository's normal deployment
workflow. No deployment is performed simply by adding this configuration.

After deployment:

1. Check `systemctl status podman-nightingale` and
   `journalctl -u podman-nightingale -f` (use `docker-nightingale` if the OCI
   backend is changed).
2. Check `podman volume inspect nightingale-data` and back up its mountpoint
   while the service is stopped. Do not use `volume rm` or prune volumes.
3. Confirm anonymous access to the HTTPS URL goes to Authelia and signed-in
   access loads the full app on the intended playback device.
4. Select/connect the intended library source, scan it and analyze a short track. On the playback device, grant
   microphone access over trusted HTTPS, select an input, play the track and
   verify scoring.
5. Separately, scan the QR code on a guest phone and complete Authelia login.
   Verify queue edits and pause/resume affect the host player. Do not expect
   microphone permission or phone audio from this guest page. Use the default
   single-window playback mode to avoid remote-start popup blocking.
6. From another LAN host, verify direct port 8783 is blocked, while snow can
   reach sleet:8783. Check backend listeners and logs if ingress returns 502.

For upgrades, verify an upstream release image, replace its digest, rebuild,
and restart through NixOS. Retain the named data volume. The CPU image is
deliberate; switch to CUDA only after a P100-compatible stack is tested.

## Considering CUDA later

Changing the image alone is insufficient. Upstream bootstrap detects
`nvidia-smi` inside the container and selects CUDA PyTorch when available;
otherwise it installs CPU PyTorch. GPU access/toolkit and a compatible driver
must also be configured. See [upstream GPU guidance](https://nightingale.cafe/docs/docker/#gpu).

Version 1.4.1's readiness check tests existing vendor files, not whether the
installed PyTorch backend matches new hardware. Therefore a persisted CPU
toolchain must not be assumed to become CUDA-enabled just by replacing the
image. Test a separate data volume first, verify the installed backend and P100
compatibility, and plan a backed-up toolchain migration. Do not delete the
production data volume to force bootstrap.
