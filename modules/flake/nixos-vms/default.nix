{
  lib,
  config,
  inputs,
  ...
}:

let
  cfg = config.auto.nixos-vms;

  qemuVmModule = inputs.nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix";

  mkBootSharedStoreConfig =
    host: configuration:
    configuration.extendModules {
      modules = [
        qemuVmModule
        (
          {
            config,
            lib,
            options,
            pkgs,
            ...
          }:
          let
            toplevel = config.system.build.toplevel;
            regInfo = pkgs.closureInfo { rootPaths = config.virtualisation.additionalPaths; };
            hasAndromedaNixDaemonSecrets =
              options ? andromeda
              && options.andromeda ? development
              && options.andromeda.development ? nixDaemonSecrets
              && options.andromeda.development.nixDaemonSecrets ? enable;
            hasHomeManager = options ? home-manager;
            waitForNixDaemon = pkgs.writeShellScript "wait-for-nix-daemon" ''
              for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
                if ${pkgs.systemd}/bin/systemctl is-active --quiet nix-daemon.service \
                  && [ -S /nix/var/nix/daemon-socket/socket ]; then
                  ${pkgs.coreutils}/bin/sleep 5
                  exit 0
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done

              exit 1
            '';

            bootImage =
              pkgs.runCommand "nixos-${host}-shared-store-boot.img"
                {
                  nativeBuildInputs = [
                    pkgs.coreutils
                    pkgs.dosfstools
                    pkgs.gnused
                    pkgs.mtools
                    pkgs.parted
                  ];
                  passthru = {
                    inherit toplevel regInfo;
                  };
                }
                ''
                  set -euo pipefail

                  esp_dir=/build/esp
                  profiles=$PWD/profiles

                  mkdir -p "$esp_dir" "$profiles/system-profiles"
                  ln -s ${toplevel} "$profiles/system-1-link"
                  ln -s system-1-link "$profiles/system"

                  cp ${config.system.build.installBootLoader} ./install-bootloader
                  chmod +w ./install-bootloader
                  substituteInPlace ./install-bootloader \
                    --replace-fail "profiles_dir = '/nix/var/nix/profiles'" \
                      "profiles_dir = os.environ.get('NIXOS_VM_PROFILES', '/nix/var/nix/profiles')" \
                    --replace-fail "profiles_dir = '/nix/var/nix/profiles/system-profiles/'" \
                      "profiles_dir = os.path.join(os.environ.get('NIXOS_VM_PROFILES', '/nix/var/nix/profiles'), 'system-profiles') + '/'"

                  HOME=$TMPDIR NIXOS_VM_PROFILES="$profiles" ./install-bootloader
                  cp ${regInfo}/registration "$esp_dir/registration"

                  esp_contents_mib=$(du -sm "$esp_dir" | cut -f1)
                  esp_mib=$((esp_contents_mib + 64))
                  if [ "$esp_mib" -lt 128 ]; then
                    esp_mib=128
                  fi
                  disk_mib=$((esp_mib + 2))
                  esp_end_mib=$((esp_mib + 1))
                  esp_blocks=$((esp_mib * 1024))

                  truncate -s "''${disk_mib}M" "$out"
                  parted --script "$out" -- \
                    mklabel gpt \
                    mkpart ESP fat32 1MiB "''${esp_end_mib}MiB" \
                    set 1 esp on
                  mkfs.vfat --offset=2048 -n ESP "$out" "$esp_blocks"
                  mcopy -s -i "$out@@1048576" "$esp_dir"/* ::
                '';
          in
          {
            _module.args.nixosVmHostName = host;

            andromeda.development.nixDaemonSecrets.enable = lib.mkIf hasAndromedaNixDaemonSecrets (
              lib.mkForce false
            );

            hardware = lib.mkIf (options.hardware ? "nvidia-container-toolkit") {
              "nvidia-container-toolkit".enable = lib.mkForce false;
            };

            services.fan2go.enable = lib.mkIf (options.services ? fan2go) (lib.mkForce false);
            services.openssh.settings.PasswordAuthentication = lib.mkIf (options.services ? openssh) (
              lib.mkForce true
            );

            systemd.services = {
              liquidcfg.enable = lib.mkForce false;
              systemd-boot-random-seed.enable = lib.mkForce false;
            }
            // lib.mapAttrs' (user: _: {
              name = "home-manager-${user}";
              value = {
                wants = [ "nix-daemon.service" ];
                after = [ "nix-daemon.service" ];
                serviceConfig.ExecStartPre = [ waitForNixDaemon ];
              };
            }) cfg.bootSharedStoreUserPasswords;

            home-manager.sharedModules = lib.mkIf hasHomeManager [
              (
                {
                  config,
                  lib,
                  options,
                  pkgs,
                  ...
                }:
                {
                  _module.args.nixosVmHostName = host;

                  systemd.user.services.agenix = lib.mkIf (options ? age && options.age ? secrets) {
                    Unit.Description = lib.mkForce "Skipped agenix activation in generated VM";
                    Service = {
                      Type = lib.mkForce "oneshot";
                      ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
                      RemainAfterExit = lib.mkForce true;
                    };
                  };
                }
              )
            ];

            boot.loader.efi = {
              canTouchEfiVariables = lib.mkForce false;
              efiSysMountPoint = lib.mkForce "/build/esp";
            };
            boot.kernelParams = [
              "regInfo=/boot/registration"
            ];
            boot.initrd.luks.devices = lib.mkForce { };

            system.build.bootSharedStoreImage = bootImage;
            swapDevices = lib.mkForce [ ];

            users.users = lib.mapAttrs (_user: initialPassword: {
              hashedPasswordFile = lib.mkForce null;
              initialPassword = lib.mkForce initialPassword;
            }) cfg.bootSharedStoreUserPasswords;

            virtualisation = {
              host.pkgs = lib.mkDefault pkgs;
              cores = lib.mkDefault 4;
              memorySize = lib.mkDefault 8192;
              resolution = lib.mkDefault {
                x = 1280;
                y = 720;
              };
              useBootLoader = true;
              useEFIBoot = true;
              useDefaultFilesystems = false;
              installBootLoader = false;
              mountHostNixStore = true;
              diskImage = null;
              bootPartition = null;

              efi.keepVariables = false;
              directBoot.enable = false;

              qemu.drives = [
                {
                  name = "esp";
                  file = "${bootImage}";
                  driveExtraOpts = {
                    format = "raw";
                    readonly = "on";
                  };
                  deviceExtraOpts = {
                    bootindex = "1";
                    serial = "esp";
                  };
                }
              ];

              fileSystems = lib.mkForce {
                "/" = {
                  device = "tmpfs";
                  fsType = "tmpfs";
                  neededForBoot = true;
                  options = [ "mode=755" ];
                };

                "/nix/.ro-store" = {
                  device = "nix-store";
                  fsType = "9p";
                  neededForBoot = true;
                  options = [
                    "trans=virtio"
                    "version=9p2000.L"
                    "msize=${toString config.virtualisation.msize}"
                    "x-systemd.requires=modprobe@9pnet_virtio.service"
                    "cache=${config.virtualisation.nixStore9pCache}"
                  ];
                };

                "/nix/store" = {
                  device = "/nix/.ro-store";
                  fsType = "none";
                  options = [ "bind" ];
                };

                "/boot" = {
                  device = "/dev/disk/by-partlabel/ESP";
                  fsType = "vfat";
                  neededForBoot = false;
                  options = [ "ro" ];
                };

                "/tmp" = lib.mkIf config.boot.tmp.useTmpfs {
                  device = "tmpfs";
                  fsType = "tmpfs";
                  neededForBoot = true;
                  options = [
                    "mode=1777"
                    "strictatime"
                    "nosuid"
                    "nodev"
                    "size=${toString config.boot.tmp.tmpfsSize}"
                  ];
                };
              };
            };
          }
        )
      ]
      ++ cfg.bootSharedStoreExtraModules;
    };
in
{
  options.auto.nixos-vms =
    let
      inherit (lib) types;
    in
    {
      enable = lib.mkEnableOption "generated NixOS VM packages and apps";

      hosts = lib.mkOption {
        description = ''
          Optional allow-list of NixOS hosts to expose as VM outputs.
          An empty list exposes all bootable NixOS hosts; apps are generated only for
          hosts native to the current flake system.
        '';
        type = types.listOf types.str;
        default = [ ];
      };

      includeBootLoader = lib.mkOption {
        description = "Expose vmWithBootLoader packages and apps for boot menu testing.";
        type = types.bool;
        default = true;
      };

      includeBootSharedStore = lib.mkOption {
        description = ''
          Expose bootloader VM packages and apps that boot through EFI while sharing
          the host /nix/store instead of building a full standalone disk image.
        '';
        type = types.bool;
        default = true;
      };

      bootSharedStoreUserPasswords = lib.mkOption {
        description = ''
          VM-only initial passwords for existing users in generated shared-store
          boot VMs. This clears each listed user's hashedPasswordFile so logins do
          not depend on host secret mounts.
        '';
        type = types.attrsOf types.str;
        default = {
          conroy = "vm";
        };
      };

      bootSharedStoreExtraModules = lib.mkOption {
        description = ''
          Extra NixOS modules appended to every generated shared-store boot VM.
          Use this for VM-only replacement or disabling of host secrets. Modules
          can take nixosVmHostName as an argument to branch on the host name.
        '';
        type = types.listOf types.deferredModule;
        default = [ ];
      };

      includeDisko = lib.mkOption {
        description = ''
          Expose vmWithDisko packages and apps for hosts that define it.
          Disabled by default because disko interactive VMs evaluate host filesystem assertions.
        '';
        type = types.bool;
        default = false;
      };
    };

  config = lib.mkIf cfg.enable {
    flake =
      let
        nixosHosts = config.auto.configurations.configurationTypes.nixos.result or { };

        selectedHosts = lib.filterAttrs (
          host: _hostConfig: cfg.hosts == [ ] || builtins.elem host cfg.hosts
        ) nixosHosts;

        bootableHosts = lib.filterAttrs (
          _host: { configuration, ... }: configuration.config.system.build ? initialRamdisk
        ) selectedHosts;

        mkHostVms =
          host:
          { configuration, meta, ... }:
          let
            builds = configuration.config.system.build;
            bootSharedStoreConfig = mkBootSharedStoreConfig host configuration;
          in
          {
            inherit meta;
            fast = builds.vm;
          }
          // lib.optionalAttrs cfg.includeBootLoader {
            boot = builds.vmWithBootLoader;
          }
          // lib.optionalAttrs cfg.includeBootSharedStore {
            bootSharedStore = bootSharedStoreConfig.config.system.build.vm;
          }
          // lib.optionalAttrs (cfg.includeDisko && builds ? vmWithDisko) {
            disko = builds.vmWithDisko;
          };
      in
      {
        nixosVms = lib.mapAttrs mkHostVms bootableHosts;
      };

    perSystem =
      {
        lib,
        system,
        ...
      }:
      let
        pkgsPure = import inputs.nixpkgs { inherit system; };
        nixosVms = config.flake.nixosVms or { };

        nativeVms = lib.filterAttrs (_host: hostVms: hostVms.meta.system == system) nixosVms;

        mkRunWrapper =
          name: vmPackage:
          pkgsPure.writeShellApplication {
            name = "run-${name}";
            text = ''
              shopt -s nullglob
              run_scripts=(${vmPackage}/bin/run-*-vm)
              if [ "''${#run_scripts[@]}" -ne 1 ]; then
                printf 'expected one VM runner in %s/bin, found %s\n' \
                  ${lib.escapeShellArg (toString vmPackage)} \
                  "''${#run_scripts[@]}" >&2
                exit 1
              fi
              exec "''${run_scripts[0]}" "$@"
            '';
          };

        testUser = lib.head (lib.attrNames cfg.bootSharedStoreUserPasswords);
        testPassword = cfg.bootSharedStoreUserPasswords.${testUser};

        mkBootSharedStoreTestWrapper =
          name: vmPackage:
          pkgsPure.writeShellApplication {
            name = "test-${name}";
            runtimeInputs = with pkgsPure; [
              coreutils
              gnugrep
              imagemagick
              netcat
              openssh
              procps
              socat
              sshpass
            ];
            text = ''
              set -euo pipefail

              tmpdir=$(mktemp -d)
              artifact_dir="''${ARTIFACT_DIR:-artifacts/${name}}"
              ssh_port="''${SSH_PORT:-22220}"
              vnc_display="''${VNC_DISPLAY:-77}"
              qmp_log="$tmpdir/qmp.log"
              qemu_log="$tmpdir/qemu.log"
              known_hosts="$tmpdir/known_hosts"

              mkdir -p "$artifact_dir"

              cleanup() {
                status=$?
                set +e
                if [ "$status" -ne 0 ]; then
                  echo "--- qemu log ---" >&2
                  cat "$qemu_log" >&2 2>/dev/null
                  echo "--- qmp log ---" >&2
                  cat "$qmp_log" >&2 2>/dev/null
                  if type guest >/dev/null 2>&1; then
                    echo "--- guest status ---" >&2
                    guest "
                      systemctl --no-pager --full status greetd.service home-manager-${testUser}.service nix-daemon.service || true
                      loginctl list-sessions || true
                      systemctl --user --no-pager --full status hyprland-session.target graphical-session.target colorshell.service || true
                      journalctl -b --no-pager -u greetd.service -n 80 || true
                    " >&2 || true
                  fi
                fi
                if [ -n "''${vm_pid-}" ]; then
                  kill "$vm_pid" 2>/dev/null
                  wait "$vm_pid" 2>/dev/null
                fi
                rm -rf "$tmpdir"
                exit "$status"
              }
              trap cleanup EXIT

              shopt -s nullglob
              run_scripts=(${vmPackage}/bin/run-*-vm)
              if [ "''${#run_scripts[@]}" -ne 1 ]; then
                printf 'expected one VM runner in %s/bin, found %s\n' \
                  ${lib.escapeShellArg (toString vmPackage)} \
                  "''${#run_scripts[@]}" >&2
                exit 1
              fi

              export HOME="$tmpdir/home"
              export NIX_EFI_VARS="$tmpdir/efi-vars.fd"
              export QEMU_NET_OPTS="hostfwd=tcp:127.0.0.1:$ssh_port-:22"
              export QEMU_OPTS="-qmp unix:$tmpdir/qmp.sock,server=on,wait=off -vnc 127.0.0.1:$vnc_display"
              mkdir -p "$HOME"

              "''${run_scripts[0]}" >"$qemu_log" 2>&1 &
              vm_pid=$!

              qmp() {
                local command="$1"
                {
                  printf '%s\n' '{"execute":"qmp_capabilities"}' "$command"
                  sleep 0.1
                } | socat - "UNIX-CONNECT:$tmpdir/qmp.sock" >>"$qmp_log" || true
              }

              send_key() {
                local key="$1"
                qmp '{"execute":"human-monitor-command","arguments":{"command-line":"sendkey '"$key"'"}}'
              }

              guest() {
                local command="$*"
                printf '%s\n' "$command" \
                  | sshpass -p ${lib.escapeShellArg testPassword} ssh \
                    -p "$ssh_port" \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile="$known_hosts" \
                    -o ConnectTimeout=5 \
                    -o PubkeyAuthentication=no \
                    -o PreferredAuthentications=password,keyboard-interactive \
                    ${lib.escapeShellArg testUser}@127.0.0.1 \
                    "bash -s"
              }

              check_guest() {
                printf 'guest> %s\n' "$*" >&2
                guest "$@"
              }

              for _ in $(seq 1 180); do
                if [ -S "$tmpdir/qmp.sock" ] && nc -z 127.0.0.1 "$ssh_port"; then
                  break
                fi
                sleep 1
              done

              test -S "$tmpdir/qmp.sock"

              sleep 20
              for _ in $(seq 1 60); do
                if guest "true" >/dev/null 2>&1; then
                  break
                fi
                sleep 1
              done

              guest "systemctl is-active --quiet greetd.service"
              guest "systemctl is-active --quiet home-manager-${testUser}.service"
              guest "systemctl --user daemon-reload"

              qmp '{"execute":"screendump","arguments":{"filename":"'"$tmpdir"'/greeter.ppm"}}'
              test -s "$tmpdir/greeter.ppm"

              for key in ${lib.concatStringsSep " " (lib.stringToCharacters testUser)} ret ${lib.concatStringsSep " " (lib.stringToCharacters testPassword)} ret; do
                send_key "$key"
                sleep 0.15
              done

              qmp '{"execute":"screendump","arguments":{"filename":"'"$tmpdir"'/typed.ppm"}}'

              for _ in $(seq 1 120); do
                if guest "systemctl --user is-active --quiet hyprland-session.target"; then
                  break
                fi
                sleep 1
              done

              check_guest "systemctl --user is-active --quiet hyprland-session.target"
              check_guest "systemctl --user is-active --quiet graphical-session.target"
              check_guest "systemctl --user is-active --quiet colorshell.service"
              check_guest "systemctl --user is-active --quiet hypr-game-submapd.service"
              check_guest "systemctl is-active --quiet home-manager-${testUser}.service"
              check_guest "test \"\$(systemctl is-system-running)\" = running"
              check_guest "test -z \"\$(systemctl --failed --no-legend --plain)\""
              check_guest "test -z \"\$(systemctl --user --failed --no-legend --plain)\""
              check_guest "test -L ~/.wayland-session"
              check_guest "test -L ~/.config/hypr/hyprland.lua"
              check_guest "test -f ~/.config/colorshell/config.overrides.json"
              check_guest "test -f ~/.config/colorshell/hyprlock.conf"
              check_guest "test -f ~/.config/xdg-desktop-portal/hyprland-portals.conf"
              check_guest "pgrep -f '[H]yprland' >/dev/null"
              check_guest "export \$(systemctl --user show-environment | grep -E '^(HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY)='); hyprctl version >/dev/null"
              check_guest "export \$(systemctl --user show-environment | grep -E '^(HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY)='); test -z \"\$(hyprctl configerrors)\""

              for _ in $(seq 1 60); do
                if guest "test -f ~/.cache/wal/colors.json"; then
                  break
                fi
                sleep 1
              done
              check_guest "test -f ~/.cache/wal/colors.json"

              # shellcheck disable=SC2016
              hypr_env='export $(systemctl --user show-environment | grep -E '"'"'^(HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY)='"'"')'
              for _ in $(seq 1 60); do
                if guest "$hypr_env; hyprctl layers | grep -F 'namespace: top-bar'"; then
                  break
                fi
                sleep 1
              done
              check_guest "$hypr_env; hyprctl layers | grep -F 'namespace: top-bar'"

              for expected in \
                '"class": "com.mitchellh.ghostty"' \
                '"class": "plexamp"' \
                '"class": "Slack"' \
                '"class": "chromium-browser"' \
                '"title": "btop"' \
                '"title": "cava"'
              do
                for _ in $(seq 1 60); do
                  if guest "$hypr_env; hyprctl clients -j | grep -F '$expected'"; then
                    break
                  fi
                  sleep 1
                done
                check_guest "$hypr_env; hyprctl clients -j | grep -F '$expected'"
              done

              qmp '{"execute":"screendump","arguments":{"filename":"'"$tmpdir"'/desktop.ppm"}}'
              test -s "$tmpdir/desktop.ppm"
              magick "$tmpdir/greeter.ppm" "$tmpdir/greeter.png"
              magick "$tmpdir/typed.ppm" "$tmpdir/typed.png"
              magick "$tmpdir/desktop.ppm" "$tmpdir/desktop.png"
              test "$(stat -c %s "$tmpdir/desktop.png")" -gt 10000

              guest "
                set -x
                systemctl is-system-running
                systemctl --failed --no-legend --plain
                systemctl --user --failed --no-legend --plain
                systemctl --user is-active hyprland-session.target graphical-session.target colorshell.service hypr-game-submapd.service
                systemctl is-active home-manager-${testUser}.service greetd.service nix-daemon.service
                loginctl list-sessions
                export \$(systemctl --user show-environment | grep -E '^(HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY)=')
                hyprctl monitors -j
                hyprctl layers
                hyprctl clients -j
                hyprctl configerrors
              " >"$tmpdir/guest-state.txt"

              cp "$tmpdir/greeter.ppm" "$artifact_dir/greeter.ppm"
              cp "$tmpdir/typed.ppm" "$artifact_dir/typed.ppm"
              cp "$tmpdir/desktop.ppm" "$artifact_dir/desktop.ppm"
              cp "$tmpdir/greeter.png" "$artifact_dir/greeter.png"
              cp "$tmpdir/typed.png" "$artifact_dir/typed.png"
              cp "$tmpdir/desktop.png" "$artifact_dir/desktop.png"
              cp "$tmpdir/guest-state.txt" "$artifact_dir/guest-state.txt"
              cp "$qemu_log" "$artifact_dir/qemu.log"
              cp "$qmp_log" "$artifact_dir/qmp.log"
              printf 'validated %s\nartifacts: %s\n' ${lib.escapeShellArg name} "$artifact_dir"
            '';
          };

        hostApps = lib.concatMapAttrs (
          host: hostVms:
          let
            mkApp = name: vmPackage: {
              type = "app";
              program = "${mkRunWrapper name vmPackage}/bin/run-${name}";
            };
          in
          {
            "vm-${host}" = mkApp "vm-fast-${host}" hostVms.fast;
            "vm-fast-${host}" = mkApp "vm-fast-${host}" hostVms.fast;
          }
          // lib.optionalAttrs (hostVms ? boot) {
            "boot-vm-${host}" = mkApp "vm-boot-${host}" hostVms.boot;
            "vm-boot-${host}" = mkApp "vm-boot-${host}" hostVms.boot;
          }
          // lib.optionalAttrs (hostVms ? bootSharedStore) {
            "boot-store-vm-${host}" = mkApp "vm-boot-store-${host}" hostVms.bootSharedStore;
            "vm-boot-store-${host}" = mkApp "vm-boot-store-${host}" hostVms.bootSharedStore;
            "test-boot-store-vm-${host}" = {
              type = "app";
              program = "${mkBootSharedStoreTestWrapper "vm-boot-store-${host}" hostVms.bootSharedStore}/bin/test-vm-boot-store-${host}";
            };
          }
          // lib.optionalAttrs (hostVms ? disko) {
            "disko-vm-${host}" = mkApp "vm-disko-${host}" hostVms.disko;
            "vm-disko-${host}" = mkApp "vm-disko-${host}" hostVms.disko;
          }
        ) nativeVms;
      in
      {
        apps = hostApps;
      };
  };
}
