# Nightingale on sleet

Nightingale is configured in `hosts/nixos/sleet/nightingale.nix`. The shared
service catalogue renders its authenticated HTTPS ingress on snow at
`https://nightingale.corncheese.org`, plus a Media homepage entry. Ensure DNS for
that name reaches snow's existing ingress before use. The existing certificate
resolver and Authelia forward-auth flow handle TLS/login; phones also need to
log in. HTTPS is required for browser microphone access and scoring.

## Runtime and data

- Upstream CPU image **1.4.1**, pinned by multi-platform digest, runs as the
  image's non-root user. No GPU device access is granted. Sleet's Tesla P100
  compatibility with upstream's downloaded PyTorch/CUDA stack is not assumed.
- Port **8783** uses the existing topology's listener/firewall policy. Only the
  ingress host is granted firewall access, not the whole LAN. Host networking
  avoids publishing a container NAT port that might bypass host firewall rules.
- Existing OPS and RED music roots are mounted read-only under `/songs`.
  The pinned library disables remote-source selection in Nightingale's UI.
- `nightingale-data` is a named OCI volume mounted at `/data`; image ownership is
  retained rather than guessing an upstream UID. Its contents include settings,
  analysis results, downloaded tools and models. Sleet already persists
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
   access loads the app. Check a phone can pair and grant microphone access.
4. Scan the library, analyze a short track, play it and verify scoring.
5. From another LAN host, verify direct port 8783 is blocked, while snow can
   reach sleet:8783. Check backend listeners and logs if ingress returns 502.

For upgrades, verify an upstream release image, replace its digest, rebuild,
and restart through NixOS. Retain the named data volume. The CPU image is
deliberate; switch to CUDA only after a P100-compatible stack is tested.
