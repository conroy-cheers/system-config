# `panda`

This host recreates the current MainsailOS printer stack on a Raspberry Pi 4 Model B Rev 1.1:

- Klipper, Moonraker, Mainsail, SSH, Avahi, Tailscale
- Wi-Fi-first boot with the extracted SSIDs from the SD image
- `can0` provided by the BTT Octopus USB bridge at `1000000` bitrate
- Mutable printer config under `/var/lib/moonraker/config`, with compatibility symlinks back to the legacy `/home/pi/*` paths
- Dedicated service users for printer services; no Raspberry Pi OS `pi` account is carried forward

## Accounts

- `conroy` is the administrative SSH user and reuses the extracted authorized key from the old `pi` account.
- `moonraker` owns the mutable printer state and also runs Klipper so both services can safely share the same writable config tree.
- `/home/pi` is retained only as a compatibility shim for legacy Klipper paths referenced by the imported config.

## Manual deployment steps

Two pieces of state are intentionally not checked into the repo:

1. The SSH host private key
2. The existing G-code library from the MainsailOS image

Because `panda` now consumes the repo's existing shared `home.wifi.conf` secret, add the host to the normal agenix rekey flow before evaluating or deploying the real machine:

```sh
agenix rekey -a
```

After building the base image, create a personalized copy with the existing ed25519 host key pair injected into `/etc/ssh`:

```sh
nix build .#nixosConfigurations.panda.config.system.build.sdImage --out-link result-image
nix build .#packages.x86_64-linux.panda-image-tool --out-link result-tool
./result-tool/bin/extract-image \
  --image ./result-image \
  --host-privkey /path/to/ssh_host_ed25519_key \
  --output ~/panda.img
```

The wrapper verifies that the supplied private key matches `panda`'s configured host recipient pubkey before modifying the image. That key is used both for SSH host identity and as the agenix recipient for the rekeyed Wi-Fi secret, so first boot will not bring up Wi-Fi without it.

To restore the large existing print library without checking 730 MiB into git:

```sh
rsync -a /tmp/panda-home/pi/gcode_files/ /mnt/var/lib/moonraker/gcodes/
```

## Firmware references

The extracted firmware build configs are preserved here for manual rebuilds and flashing:

- `firmware-configs/octopus-klipper.config`
- `firmware-configs/sb2040-klipper.config`
- `firmware-configs/octopus-katapult.config`
- `firmware-configs/sb2040-katapult.config`

Image-derived revisions for reference:

- Klipper `5493bdfb483f59935381703b1e1cedb466e8586d`
- Moonraker `7cdcca3cb4b7caf27d511d1c4e32fa3297391709`
- Mainsail `v2.13.2`
- Katapult `bc1ecea7f7fb336d067d0eb166a48be920dc7035`
