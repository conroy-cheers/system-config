{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  imports = [ inputs.disko.nixosModules.disko ];

  environment.systemPackages = with pkgs; [
    # `statfs` for btrfs commands
    gocryptfs
  ];

  # If on installer
  disko.enableConfig = true;

  # `head -c 8 /etc/machine-id`
  networking.hostId = "43a367e3";

  # NOTE: needed for mounting `/key` (for LUKS)
  boot.initrd.kernelModules = [
    "uas"
    "ext4"
  ];

  # HACK: for troubleshooting
  # see https://github.com/NixOS/nixpkgs/blob/9d6655c6222211adada5eeec4a91cb255b50dcb6/nixos/modules/system/boot/stage-1-init.sh#L45-L49
  # boot.initrd.preFailCommands = ''
  #   export allowShell=1
  # '';

  # NOTE: doesn't get mounted early enough, see below
  # fileSystems."/key" = {
  #   device = "/dev/disk/by-partlabel/key";
  #   fsType = "ext4";
  #   neededForBoot = true;
  # };

  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "defaults"
        "size=16G"
        "mode=755"
      ];
    };

    disk = {
      nvme1n1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              label = "boot";
              name = "ESP";
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
              };
            };
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                extraOpenArgs = [
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                settings = {
                  allowDiscards = true;
                  # https://0pointer.net/blog/unlocking-luks2-volumes-with-tpm2-fido2-pkcs11-security-hardware-on-systemd-248.html
                  crypttabExtraOpts = [
                    "fido2-device=auto"
                    "token-timeout=10"
                  ];
                };
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "nixos"
                    "-f"
                  ];
                  subvolumes = {
                    home = {
                      mountpoint = "/home";
                      mountOptions = [
                        "subvol=home"
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    nix = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "subvol=nix"
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    persist = {
                      mountpoint = "/persist";
                      mountOptions = [
                        "subvol=persist"
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    log = {
                      mountpoint = "/var/log";
                      mountOptions = [
                        "subvol=log"
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    tmp = {
                      mountpoint = "/tmp";
                      mountOptions = [ "noatime" ];
                    };
                    swap = {
                      mountpoint = "/swap";
                      swap.swapfile.size = "64G";
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}
