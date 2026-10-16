# bouba

Valve Steam Frame, using the hardware and session modules from
`steam-frame-nixos`. The shared Nixpkgs lock matches that repo's validated
`151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4` revision.

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

The nested Hyprland package uses scoped Aquamarine fixes for protocol negotiation and initial window configuration.
Frame's own Mesa, gamescope, SteamVR, audio and login services remain responsible
for the outer session. The desktop connects directly to Gamescope over Wayland,
using Frame’s surface metadata protocol and a software cursor.
Set `programs.steamvr.nestedDesktop.transport = "x11"` to restore the Weston bridge.

While the upstream Frame module changes are local, build/deploy with:

```sh
nix develop -c deploy .#bouba --skip-checks -- \
  --override-input steam-frame-nixos ~/src/steam-frame-nixos
```

Update the remote input pin after publishing that repo's changes. Until then,
the override is required for this desktop configuration.

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
