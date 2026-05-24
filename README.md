<!-- <div align="center">
    <p>
        <a href="https://github.com/NixOS">
            <img src="https://img.shields.io/badge/NixOS?style=flat-square&logo=nix" alt="NixOS"/>
        </a>
        <a href="https://github.com/t184256/nix-on-droid">
            <img src="https://img.shields.io/badge/nix%2Don%2Ddroid?style=flat-square&logo=nix" alt="nix-on-droid"/>
        </a>
        <a href="https://github.com/LnL7/nix-darwin">
            <img src="https://img.shields.io/badge/nix%2Ddarwin?style=flat-square&logo=nix" alt="nix-darwin"/>
        </a>
    </p>
</div> -->

<!-- TODO: badges? -->
<div align="center">
</div>

---

# Structure

- Everything is built upon [flake-parts](https://flake.parts/), with [flake modules](./modules/flake/) for automatic packages, modules && configurations extraction
  - Automatic classic (`callPackage`) and `dream2nix` packages extraction
  - Automatic `nixos`, `nix-darwin`, `nix-on-droid`, `home-manager` and `flake` modules extraction
  - Automatic `nixos`, `nix-darwin`, `nix-on-droid` and `home-manager` configurations extraction
- Hosts can be found under `./hosts/${config-type}/${system}/${hostname}/...`
  - Check [`./modules/flake/configurations.nix`](./modules/flake/configurations.nix) for more info on what is extracted from those directories
- Modules can be found under `./modules/${config-type}/...`
  - Check [`./modules/flake/modules.nix`](./modules/flake/modules.nix) for more info on what is extracted from that directory
- Packages can be found under `./pkgs/...`
- Overlays can be found under `./overlays/...`
- Shells can be found under `./shells/...`
  - Default one puts a recent `nix` together with some other useful tools for working with the repo (`deploy-rs`, `rage`, `agenix-rekey`, etc.), see [`./shells/default/default.nix`](./shells/default/default.nix) for more info

# Topology

You can see the overall topology of the hosts by running

```sh
nix build .#topology
```

And opening the resulting `./result/main.svg` and `./result/network.svg`

---

# Host VMs

NixOS hosts with a normal initrd get generated VM outputs under `nixosVms`.

```sh
# Fast VM for quick config smoke testing
nix run .#vm-brick
nix build .#nixosVms.brick.fast

# Bootloader VM for boot menu testing without copying the full store closure
nix run .#boot-store-vm-brick
nix build .#nixosVms.brick.bootSharedStore

# Automated boot-store VM validation: greeter login and desktop health
nix run .#test-boot-store-vm-brick

# Standalone bootloader VM; slower because it builds a full disk image
nix run .#boot-vm-brick
nix build .#nixosVms.brick.boot
```

The app names are generated per host:

- `vm-${host}` / `vm-fast-${host}` run `system.build.vm`
- `boot-store-vm-${host}` / `vm-boot-store-${host}` run an EFI bootloader VM
  with a small generated boot disk and the host `/nix/store` mounted read-only
- `test-boot-store-vm-${host}` boots the shared-store VM, captures greeter and
  desktop screenshots, logs in with the VM credentials through QEMU keyboard
  events, and asserts that Home Manager, Hyprland, colorshell, and system/user
  units are healthy
- `boot-vm-${host}` / `vm-boot-${host}` run `system.build.vmWithBootLoader`

The shared-store boot VM runs the host bootloader installer against a synthetic
single-generation profile, so bootloader styling, menu entries, kernel/initrd
copying, and boot splash behavior come from the host configuration. Its VM-only
overrides are limited to the temporary ESP mount path, EFI variable handling,
tmpfs root/shared-store mounts, disabled host disk unlock/swap, and hardware
assertions that do not apply inside QEMU.

The VM does not mount the real host `/persist` volume or decrypt host agenix
secrets. For interactive login testing, `auto.nixos-vms.bootSharedStoreUserPasswords`
defaults to giving the existing `conroy` account a VM-only password:

```text
username: conroy
password: vm
```

Common VM-only secret substitutions can be applied to every shared-store boot VM
with `auto.nixos-vms.bootSharedStoreExtraModules`. Those modules are appended to
the generated VM config and can take `nixosVmHostName` as an argument for
host-specific overrides:

```nix
auto.nixos-vms.bootSharedStoreExtraModules = [
  (
    { lib, nixosVmHostName, ... }:
    lib.mkIf (nixosVmHostName == "brick") {
      # VM-only secret and service overrides go here.
    }
  )
];
```

Disko interactive VMs can be enabled through `auto.nixos-vms.includeDisko`, but
they are disabled by default because they evaluate host filesystem assertions.

---

# Secrets

Secrets are managed by [`agenix`](https://github.com/ryantm/agenix) and [`agenix-rekey`](https://github.com/oddlama/agenix-rekey)

> [!NOTE]
> Secrets are defined by the hosts themselves, `agenix-rekey` *just* collects what secrets are referenced by them and lets you generate, edit and rekey them

```sh
# To put `rage`, `agenix-rekey` and friends in `$PATH`
nix develop
```

## Edit secret

```sh
# Select from `fzf` menu
agenix edit
```

## Rekey all secrets

```sh
agenix rekey
```

## Generate missing keys (with the defined `generators`)

```sh
agenix generate
```

---

# Setups

## NixOS setup

```sh
# Initial setup
nix run nixpkgs#nixos-anywhere -- --flake ".#${HOSTNAME}" --build-on-remote --ssh-port 22 "root@${HOSTNAME}" --no-reboot

# Deploy
deploy ".#${HOSTNAME}" --skip-checks
```

## MacOS / Darwin (silicon) setup

```sh
# Setup system tools
softwareupdate --install-rosetta --agree-to-license
sudo xcodebuild -license

# Install nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Apply configuration
git clone https://www.github.com/conroy-cheers/system-config ~/.config/system-config
cd ~/.config/system-config
nix build ".#darwinConfigurations.${HOSTNAME}.system"
./result/sw/bin/darwin-rebuild switch --flake .

# System setup for `yabai` (in system recovery)
# NOTE: <https://support.apple.com/guide/mac-help/macos-recovery-a-mac-apple-silicon-mchl82829c17/mac>
csrutil enable --without fs --without debug --without nvram
```

---

# Credits

Based on [`reo101`](https://github.com/reo101)'s [`rix101`](https://github.com/reo101/rix101) config.
