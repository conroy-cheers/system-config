# AGENTS.md

- This repo is the `system-config` flake for NixOS, nix-darwin, nix-on-droid,
  Home Manager, packages, overlays, shells, and deploy-rs nodes.
- Flake-parts auto-discovers hosts under `hosts/${type}/${hostname}`, modules
  under `modules/${type}`, packages under `pkgs`, overlays under `overlays`, and
  shells under `shells`.
- Use `nix develop` for repo tools such as `deploy`, `agenix-rekey`, `rage`,
  `home-manager`, and related secret/deploy utilities.
- Format Nix with `nix fmt`; the flake formatter is `nixfmt-tree`.

## Rebuild And Deploy

- For this machine, use `rebuild` to rebuild the system. It defaults to
  `switch`; use `rebuild build` for a local build-only proof.
- For direct host proofs, prefer targeted commands such as
  `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath --show-trace`
  or `sudo -n nixos-rebuild build --flake .#<host>` before broad checks.
- Deploy a remote host with `deploy .#example-hostname --skip-checks`.
- Common NixOS hosts include `brick`, `kombu`, `labtop`, `panda`, `sleet`,
  `snow`, and `wsl-brick`; `kiki` is nix-darwin.

## Server Config Input

- Server config usually has a checkout at `~/src/corncheese-server-config`.
- When work involves server config, first ensure that checkout exists and is up
  to date.
- When changing any host that uses server config, edit the
  `~/src/corncheese-server-config` checkout where applicable.
- Deploy those changes with an override, for example:
  `deploy .#example-hostname --skip-checks -- --override-input corncheese-server ~/src/corncheese-server-config/`
- `sleet` imports `inputs.corncheese-server.nixosModules.corncheese-server`.

## Secrets

- Secrets use `agenix`, `ragenix`, and `agenix-rekey`.
- From `nix develop`, use `agenix edit`, `agenix rekey`, and `agenix generate`
  for secret maintenance.
- Secret material lives under `secrets/`; rekeyed host outputs live under
  `secrets/rekeyed/<host>`.
