# shrimpus

Orange Pi Zero 2W (Allwinner H618), using an SD card and onboard UWE5622 Wi-Fi.
The board module supplies an SDIO device-tree overlay, Armbian's external driver,
and its firmware/calibration file. Bluetooth is not configured.
The first boot reported 964684 KiB of RAM, consistent with the 1 GiB model.
The red LED indicates power; the green LED uses the Linux heartbeat trigger.

The host uses NixOS's minimal profile and upstream Nix while retaining the Nix
daemon for deploy-rs. Installer tools, desktop data, the system flake registry,
and unrelated arm64 device trees are omitted. The resulting system closure is
about 808 MiB (847 MB decimal). Deploy with:

```sh
deploy .#shrimpus --skip-checks
```

## Network and login

- Wi-Fi joins `floznet-7` or `Abi_Wifi` using the shared `home.wifi.conf` secret.
- The interface is `wlan0`, with DHCP and Australian regulatory settings.
- Connect with `ssh -i ~/.ssh/conroy_home.id_ed25519.pub conroy@shrimpus.local`
  using the corresponding key in your SSH agent.
- `conroy` has passwordless sudo. SSH password and keyboard-interactive login
  are disabled; the public login key comes from the shared SSH identity inventory.

## First-boot secrets

The SSH **host** key is also the agenix recipient. Its public key is in
`meta.nix`; its private key must stay outside Git and the Nix store.
The initial key was generated at:

```text
~/.local/share/system-config/shrimpus/ssh_host_ed25519_key
```

The committed ciphertext is already rekeyed for shrimpus. If the shared Wi-Fi
secret or SSH host recipient changes, rekey with the repository's FIDO2 master
identity:

```sh
nix develop -c agenix rekey -a
```

Rekeying requires the configured security key to be connected and touched.
Build the image using the real ciphertext:

```sh
nix build .#nixosConfigurations.shrimpus.config.system.build.sdImage --out-link result-shrimpus
```

Builds can run on the remote ARM64 builder or this Mac's native Linux builder.
The Mac's default 8 GiB builder VM is too small for a patched kernel build;
increase its memory to 15 GiB for that step. The board kernel omits unrelated
drivers and four netfilter modules whose names collide on the Mac-backed
case-insensitive builder filesystem. The SD image module also works around
the builder's case-renamed ncurses terminal entry when assembling the initrd.

Before flashing, inject the matching private host key into a **copy** of the
image. This tool runs directly on macOS or Linux using `debugfs`; it needs no
root privileges, mounted filesystems, or guest VM. Allow space for the raw
image plus a temporary copy of its root partition.

```sh
nix run .#personalize-sd-image -- \
  --image result-shrimpus/sd-image/shrimpus.img \
  --host-privkey ~/.local/share/system-config/shrimpus/ssh_host_ed25519_key \
  --expected-host-pubkey "$(nix eval --impure --raw --expr '(import ./hosts/nixos/shrimpus/meta.nix).pubkey')" \
  --output ~/.local/share/system-config/shrimpus/shrimpus-personalized.img
```

The tool requires an MBR image with one Linux partition labeled `NIXOS_SD`.
It checks the expected public key, reads both injected key files back, verifies
root ownership and permissions, and checks filesystem integrity before
publishing the result with mode 0600. Existing outputs require `--force`;
failed operations leave them intact. Keep the personalized image private:
it contains the SSH host private key. The source image stays unchanged.

The unpersonalized
image cannot decrypt Wi-Fi credentials; a freshly generated host key on the
board will not match the configured recipient.

## Recovery and diagnostics without UART

The supplicant restarts after a failure. A device-arrival rule starts it if
`wlan0` appears late. An early-boot health check also attempts to reprobe an
unbound Wi-Fi platform device up to three times, then stops its timer once the
interface appears or the retry limit is reached. It does not unload a live
driver or automatically reboot. Hardware/firmware failures may still require a
power cycle.

Starting around 30 seconds into Linux boot, snapshots are saved again after 2,
5 and 10 minutes to the FAT partition:

```text
SHRIMPUS/READ-ME.txt
SHRIMPUS/current/boot-id
SHRIMPUS/current/status.txt
SHRIMPUS/current/kernel.txt
SHRIMPUS/current/network.txt
SHRIMPUS/previous/...
```

If SSH never becomes available, allow a few minutes for startup/recovery, power
off, and put the card back in this Mac. Open the `FIRMWARE` volume and inspect
these files. Compare `boot-id` and timestamps to avoid mistaking an earlier
boot's snapshot for a fresh one. Snapshots include IP addresses and service
failures but do not copy credential files. Kernel and network snapshots are
each capped at 1 MiB; only the current and preceding boot are retained.

The exporter needs Linux to reach systemd and mount FAT. Missing snapshots
cannot distinguish bootloader, kernel, initrd, or filesystem failures. It does
not replace UART for those failures. Persistent journals on the ext4 partition
are capped at 100 MiB and synced every 60 seconds; unplugging power can still
lose recent writes. After SSH works, use `sudo poweroff` before removing power.

## Hardware validation

The `sun50i-cpufreq-nvmem` module loads at boot and selects operating points
from the H618 speed-grade efuse. Sustained Wi-Fi and SD activity caused abrupt
resets at this chip's 1.416 GHz maximum, including with a replacement supply,
so the device tree currently caps it at 1.2 GHz while retaining lower DVFS
states. Revisit that cap only with repeatable power and thermal testing.

Check the router's DHCP leases if `shrimpus.local` does not resolve, and connect
to that IP address with the same SSH key. Once connected, check:

```sh
free -h
ip -br address show wlan0
systemctl status shrimpus-wifi-secrets wpa_supplicant-wlan0 dhcpcd sshd
journalctl -b -k | grep -Ei 'mmc|sdio|sprd|wcn|firmware'
sudo wpa_cli -i wlan0 status
```

Module compilation and device-tree checks do not verify radio operation. A
successful hardware test must include association, DHCP, SSH, and a reboot
that reconnects without intervention.
