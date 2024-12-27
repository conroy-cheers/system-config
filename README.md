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
