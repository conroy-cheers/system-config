# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, lib, pkgs, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.impermanence.nixosModules.impermanence
  ];

  system.impermanence.enable = true;

  ### Set boot options
  boot = {
    # Use the systemd-boot boot loader.
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Enable running aarch64 binaries using qemu
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "wasm32-wasi"
        "x86_64-windows"
      ];
    };

    supportedFilesystems = lib.mkForce [ "btrfs" ];
  };

  networking.hostName = "kombu"; # Define your hostname.
  ### Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  ### Set your time zone.
  time.timeZone = "Australia/Melbourne";

  ### Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  ### Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  nix = {
    package = pkgs.nixVersions.stable;

    # Enable flakes, the new `nix` commands and better support for flakes in it
    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      trusted-users = [
        "root"
        "conroy"
      ];

      # Add nix-community cachix cache
      substituters = [
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  ### Fonts
  fonts.fontconfig.enable = true;

  hardware.graphics.enable = true;
  environment.sessionVariables = {
    "_JAVA_AWT_WM_NONREPARENTING" = "1";
    "LIBVA_DRIVER_NAME" = "nvidia";
    "XDG_SESSION_TYPE" = "wayland";
    "GBM_BACKEND" = "nvidia-drm";
    "__GLX_VENDOR_LIBRARY_NAME" = "nvidia";
    "WLR_NO_HARDWARE_CURSORS" = "1";
    "MOZ_DISABLE_RDD_SANDBOX" = "1";
    "MOZ_ENABLE_WAYLAND" = "1";
    "EGL_PLATFORM" = "wayland";
    "XDG_CURRENT_DESKTOP" = "sway"; # river
    "XKB_DEFAULT_LAYOUT" = "us,bg";
    "XKB_DEFAULT_VARIANT" = ",phonetic";
    "XKB_DEFAULT_OPTIONS" = "caps:escape,grp:lalt_lshift_toggle";
    # "WLR_RENDERER" = "vulkan"; # BUG: river crashes
  };

  ### Wayland specific
  services.xserver = {
    enable = true;
    displayManager = {
      defaultSession = "river";
      sessionPackages = with pkgs; [
        river
      ];
      gdm = {
        enable = true;
        wayland = true;
      };
    };
  };

  # Enable desktop portal
  xdg.portal = {
    enable = true;
    wlr = {
      enable = true;
    };
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
    ];
    # TODO: research <https://github.com/flatpak/xdg-desktop-portal/blob/1.18.1/doc/portals.conf.rst.in>
    config.common.default = "*";
  };

  ## X11 specific
  services.xserver = {
    layout = "us,bg";
    xkbVariant = ",phonetic";
    xkbOptions = "grp:lalt_lshift_toggle";
  };

  ### Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      # Forbid root login through SSH.
      PermitRootLogin = "no";
      # Use keys only. Remove if you want to SSH using password (not recommended)
      PasswordAuthentication = false;
    };
  };

  ### Enable CUPS to print documents.
  services.printing.enable = true;

  ### Enable sound.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse = {
      enable = true;
    };
    jack = {
      enable = true;
    };
  };
  services.dbus = {
    enable = true;
    packages = [ pkgs.dconf ];
  };

  ### Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Virtualisation
  virtualisation.docker.enable = true;

  ### Define a user account. Don't forget to set a password with `passwd`.
  users.users.conroy = {
    isNormalUser = true;
    initialHashedPassword = "$y$j9T$U4oXLH8mEWo00rPOaGH7b.$wt8j7UhvJriW7A/0V3jOKJte7ArPOvtX3F45i46aIR2";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB"
    ];
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "docker" ];
  };

  programs.zsh = {
    enable = true;
  };

  ### Enable plymouth (bootscreen customizations)
  boot.plymouth = {
    enable = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    river
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    neovim
    wget
    git
  ];

  ### Transmission
  services.transmission = {
    enable = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
