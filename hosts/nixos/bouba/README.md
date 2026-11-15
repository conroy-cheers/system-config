# bouba

Valve Steam Frame, using the hardware and session modules from
`steam-frame-nixos`, which follows this repository's Nixpkgs. Generation 52
(2026-11-15) is the shared lock's Nixpkgs `3ec6363` with steam-frame-nixos
`7169a61`; its exact system was trial-booted before becoming the default.
Generation 51 (Nixpkgs `151fa4e`, 2026-10-17) remains in the boot menu.

The session and Home Manager run as `conroy` (UID 1000), with `/home/conroy`.
The common shell module supplies Fish, Starship, direnv, zoxide and local Atuin
history (sync is disabled). Catppuccin theming, common Git settings, GPG, Neovim,
vifm, ripgrep, btop and cava provide the lightweight parts of Brick's user setup.
The development suites remain disabled. Nebula is enabled independently at
`10.42.42.11`, using the shared mesh CA and a host-rekeyed private key. Personal VR applications and settings belong in
`home/conroy.nix` under `programs.steamvr` and apply at session restart.

Storage uses the already provisioned NixOS-only layout: tmpfs root, persistent
Btrfs subvolumes, and preservation for machine identity, SSH and Wi-Fi profiles.
No partition provisioning is needed. The existing loader A enters the generation
menu; rebuilds publish a new catalog without rewriting firmware environment.
An SSH-first recovery configuration is included in the menu.

Console palette theming is disabled: Valve U-Boot's extlinux `APPEND` buffer is
512 bytes including its terminating NUL, and Stylix's three VT palettes made
Bouba's lines exceed it. The symptom was a dim logo while U-Boot rejected each
entry with `bootarg overflow`; Linux had not started. Application theming stays
enabled. The Frame module also rejects oversized arguments during the system
build and before publishing a boot catalog. To capture early boot over USB, power
on while holding Volume Down + Select/Aux (release Power first). This enables the
USB ACM console with a
20-second boot delay. The pinned SSH-first recovery also provides the setup AP.

Recovery on 2026-10-17 republished the existing generations with only the VT
palette arguments omitted, retaining recovery and independent RAM rescue.
An ordinary reboot selected the intended default, boot acknowledgement and
retention succeeded, no system units failed, and SteamVR was confirmed working.
Saved loader environments and firmware hashes were unchanged.

Kernel-owned CDSP loading is enabled with
`hardware.steam-frame.dsp.remoteproc.enable`. Live testing on 2026-10-17 booted
the patched kernel, verified the system firmware and remoteproc state, passed
three complete session/DSP restart cycles, and resumed from RTC-timed deep
sleep. The user reports head and controller tracking working well. Gaze,
passthrough and audible audio still need physical validation. Stop/start tests
should use the full
`steam-frame-session.service` before cycling `steam-frame-tracking-dsp.service`.
The 2026-11-15 update moved to the shared lock's Nixpkgs. Its remoteproc
driver adds the CDSP secondary memory bank (128 MiB at `0x90000000`, granted
only to images that declare it; Valve's images are unaffected). Before it
became the default, the exact system was booted once under the Frame repo's
guarded trial (`tools/kernel-trial`): ADSP, CDSP and CVP ran Valve's images,
the session, Wi-Fi and PipeWire services were active with no failed
units, and QNN hardware trials on both bank paths passed with verified stock
recovery. Ordinary builds and deployments need no override:

```sh
nix develop -c deploy .#bouba --skip-checks --boot
```

`direnv-instant`'s PTY timing tests fail in build isolation on the Frame as
on panda, so its checks are disabled here. Frame packages build natively on
the device (Valve's Mesa, kernel and patched session components are not in a
binary cache): copy the derivation with `nix copy --derivation` and realise it
there, or let deploy-rs use a remote aarch64 builder.

`deploy.nix` embeds deploy-rs activation helpers directly into the NixOS
toplevel. The host generator uses `system.build.deploy` when supplied, keeping
Frame profile paths compatible with its guarded boot installer.

Deploy with:

```sh
nix develop -c deploy .#bouba --skip-checks
```

The first deployment uses the existing address and root account:

```sh
nix develop -c deploy .#bouba --skip-checks \
  --hostname 10.1.0.54 --ssh-user root \
  --ssh-opts '-o IdentitiesOnly=yes -o HostKeyAlias=steam-frame.lan -i ~/.ssh/conroy_home.id_ed25519.pub'
```

For migration, stop the Frame session and UID 1000's user manager before copying
`/var/lib/steam-frame-test` to `/home/conroy` with Btrfs reflinks. Retain the old
home and pin the old system closure for rollback. Rewrite absolute Steam home
symlinks and text preferences in the new copy, then rename the account before
activating the new configuration. Never rewrite binary shortcut databases as
text.

The initial migration retained the original home at
`/var/lib/steam-frame-test` and pinned the previous system with
`/nix/var/nix/gcroots/bouba-pre-migration`. Keep both until satisfied with the
new session; booting the old generation uses the original `deck` home.

A config snapshot is installed at `/home/conroy/.config/system-config`. The
current private input sources are retained under
`/nix/var/nix/gcroots/bouba-flake-inputs` so this revision can be evaluated
locally without copying GitHub credentials to the device.

## Desktop inside VR

`steam-frame-desktop` launches Corncheese Desktop as one SteamVR panel. It uses
`corncheese.wm.sessionMode = "nested"`: normal layout, bindings and Catppuccin
styling, with the shared Colorshell, Ghostty, Thunar and Chromium configuration. Alt+Return opens a terminal,
Alt+Space opens the app launcher, Alt+T opens the file manager, Alt+F opens the
browser, and Alt+Ctrl+Delete exits the nested desktop. Development suites remain
disabled. Workstation autostarts, locking, global portals and login-session
integration are excluded; Colorshell, hyprpaper and GTK portals run on the private
desktop bus. The common terminal module supplies the theme's Nerd Font and emoji
font without enabling development tools.

Bouba selects `corncheese.wm.package` explicitly. The shared WM module does not
inspect SteamVR settings. Its nested Hyprland package and all Aquamarine patches
live in system-config; the Frame flake exposes the protocol XML through
`lib.desktopProtocol`. The package also disables Hyprland's systemd environment,
target and notification integration, keeping the Frame launcher compositor-neutral.
The nested package uses scoped Aquamarine fixes for protocol negotiation and initial window configuration.
Frame's own Mesa, gamescope, SteamVR, audio and login services remain responsible
for the outer session. The desktop connects directly to Gamescope over Wayland,
using Frame’s surface metadata protocol and a software cursor.
Set `programs.steamvr.nestedDesktop.transport = "x11"` to restore the Weston bridge.

To test unpublished Frame module changes, build/deploy with
`-- --override-input steam-frame-nixos ~/src/steam-frame-nixos`, then publish
that repository and update the input pin.

The nested desktop opts into per-pixel transparency using
`programs.steamvr.nestedDesktop.transparent`. Corncheese's
`transparentBackground` follows that option: it skips wallpaper startup, clears
the Hyprland background to alpha zero, and uses an ARGB nested output. The saved
wallpaper remains available when transparent mode is disabled. The usual
Colorshell, terminal, theme and bindings are reused. Development tools remain
disabled. The Frame input supplies the native Wayland registration protocol and the
per-window Gamescope OpenVR support; no global VR transparency switch is used.

Native desktop timing follows Gamescope's Wayland frame callbacks. The monitor
uses its parent-derived preferred refresh rate instead of a fixed 60 Hz mode;
Aquamarine forwards separate presentation timestamps from Gamescope. The X11
fallback uses the same 1920×1080 resolution at 60 Hz.

Earlier timing validation (2026-10-15, before the switch to 1080p): the native output reported 1280×800 at
120 Hz with no Hyprland configuration errors. An eight-second
`weston-presentation-shm -f` run inside the desktop measured a median presentation
interval of 8,333 µs both before and after the timing change. Previously the mode
reported 60 Hz and presentation events used callback-time guesses; the adapter
now forwards Gamescope's monotonic timestamps and sequence numbers. This checks
cadence and protocol plumbing, not physical display latency. Live headset
refresh-rate switching has not been tested.

The desktop has a fixed 1920×1080 resolution at scale 1. SteamVR panel resizing
scales the image without changing desktop space. The adaptive sizing experiment
and its protocol, configuration options and patches have been removed.
