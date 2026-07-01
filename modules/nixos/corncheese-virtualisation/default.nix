{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.virtualisation;

  inherit (lib)
    concatMapStringsSep
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    types
    ;

  vmHost = cfg.vmHost;
  lookingGlass = vmHost.lookingGlass;
  vfio = vmHost.vfio;
  inputPassthrough = vmHost.inputPassthrough;

  vmUserGroups = [
    "kvm"
    "libvirtd"
  ]
  ++ optional inputPassthrough.enable "input";

  qemuCgroupDeviceAcl = [
    "/dev/null"
    "/dev/full"
    "/dev/zero"
    "/dev/random"
    "/dev/urandom"
    "/dev/ptmx"
    "/dev/kvm"
    "/dev/kqemu"
    "/dev/rtc"
    "/dev/hpet"
    "/dev/vfio/vfio"
  ]
  ++ optional lookingGlass.enable "/dev/kvmfr0";

  qemuCgroupDeviceAclLines = concatMapStringsSep "\n" (
    device: "  \"${device}\","
  ) qemuCgroupDeviceAcl;
in
{
  options.corncheese.virtualisation = {
    vmHost = {
      enable = mkEnableOption "general-purpose QEMU/libvirt VM host tooling";

      users = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "conroy" ];
        description = lib.mdDoc ''
          Existing local users allowed to manage system libvirt VMs and access
          KVM-backed VM devices.
        '';
      };

      spiceUSBRedirection.enable = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Enable SPICE USB redirection support for interactive guests.
        '';
      };

      inputPassthrough.enable = mkEnableOption "input group access for evdev HID passthrough";

      windowsGuestTools.enable = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Install public Windows guest driver media packages for virtio and
          SPICE devices.
        '';
      };

      lookingGlass = {
        enable = mkEnableOption "Looking Glass client and kvmfr host support";

        staticMemoryMB = mkOption {
          type = types.ints.positive;
          default = 128;
          description = lib.mdDoc ''
            Static kvmfr shared-memory size, in megabytes.
          '';
        };
      };

      vfio = {
        enable = mkEnableOption "VFIO kernel support for PCI passthrough";

        iommuKernelParams = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "amd_iommu=on"
            "iommu=pt"
          ];
          description = lib.mdDoc ''
            Extra kernel parameters needed for the host IOMMU/VFIO setup.
          '';
        };

        pciIds = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "1002:73bf"
            "1002:ab28"
          ];
          description = lib.mdDoc ''
            Optional PCI vendor:device IDs to bind to vfio-pci early in boot.
          '';
        };
      };
    };
  };

  config = mkIf vmHost.enable (mkMerge [
    {
      security.polkit.enable = true;

      programs = {
        dconf.enable = true;
        virt-manager.enable = true;
      };

      virtualisation = {
        libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_full;
            swtpm.enable = true;
            vhostUserPackages = [ pkgs.virtiofsd ];
          };
        };

        spiceUSBRedirection.enable = vmHost.spiceUSBRedirection.enable;

        libvirtd.qemu.verbatimConfig = lib.mkAfter ''
          cgroup_device_acl = [
          ${qemuCgroupDeviceAclLines}
          ]
        '';
      };

      environment.systemPackages =
        with pkgs;
        [
          jq
          OVMF
          pciutils
          qemu_full
          socat
          spice-gtk
          swtpm
          usbutils
          virtiofsd
          virt-viewer
          xorriso
        ]
        ++ optional vmHost.windowsGuestTools.enable virtio-win
        ++ optional vmHost.windowsGuestTools.enable win-spice
        ++ optional lookingGlass.enable looking-glass-client;

      users.users = lib.genAttrs vmHost.users (_: {
        extraGroups = vmUserGroups;
      });
    }

    (mkIf lookingGlass.enable {
      boot = {
        extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
        extraModprobeConfig = ''
          options kvmfr static_size_mb=${toString lookingGlass.staticMemoryMB}
        '';
        kernelModules = [ "kvmfr" ];
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660", TAG+="uaccess"
      '';
    })

    (mkIf vfio.enable {
      boot = {
        extraModprobeConfig = ''
          softdep amdgpu pre: vfio-pci
          softdep snd_hda_intel pre: vfio-pci
        '';
        initrd.kernelModules = [
          "vfio"
          "vfio_iommu_type1"
          "vfio_pci"
        ];
        kernelParams =
          vfio.iommuKernelParams
          ++ optional (vfio.pciIds != [ ]) "vfio-pci.ids=${lib.concatStringsSep "," vfio.pciIds}";
      };
    })
  ]);
}
