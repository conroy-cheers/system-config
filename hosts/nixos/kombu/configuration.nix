# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, lib, pkgs, config, ... }:

{
  imports = [
    inputs.stylix.nixosModules.stylix
    ./hardware-configuration.nix
    ./disko.nix
    inputs.impermanence.nixosModules.impermanence
    ./impermanence.nix
    ./network.nix
    ./wm/hyprland.nix
    ./themes/stylix.nix
  ];

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
        "https://hyprland.cachix.org"
        "s3://andromedarobotics-artifacts?region=ap-southeast-2"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-cache.dromeda.com.au-1:x4QtHKlCwaG6bVGvlzgNng+x7WgZCZc7ctrjlz6sDHg="
      ];
    };
  };

  # nopasswd for sudo
  security.sudo-rs = {
    enable = true; # !config.security.sudo.enable;
    inherit (config.security.sudo) extraRules;
  };
  security.sudo = {
    enable = false;
    extraRules = [
      {
        users = [
          "conroy"
        ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ]; # "SETENV" # Adding the following could be a good idea
          }
        ];
      }
    ];
  };

  ### Fonts
  fonts.fontconfig.enable = true;

  hardware.graphics.enable = true;
  # environment.sessionVariables = {
  #   # "_JAVA_AWT_WM_NONREPARENTING" = "1";
  #   "XDG_SESSION_TYPE" = "wayland";
  #   # "WLR_NO_HARDWARE_CURSORS" = "1";
  #   "MOZ_DISABLE_RDD_SANDBOX" = "1";
  #   "MOZ_ENABLE_WAYLAND" = "1";
  #   "EGL_PLATFORM" = "wayland";
  #   # "XDG_CURRENT_DESKTOP" = "sway"; # river
  #   "XKB_DEFAULT_LAYOUT" = "us";
  #   "XKB_DEFAULT_VARIANT" = ",phonetic";
  #   "XKB_DEFAULT_OPTIONS" = "caps:escape,grp:lalt_lshift_toggle";
  #   # "WLR_RENDERER" = "vulkan"; # BUG: river crashes
  # };

  # services.displayManager = {
  #   # defaultSession = "river";
  #   sessionPackages = with pkgs; [
  #     hyprland
  #   ];
  # };

  ### Wayland specific
  services.xserver = {
    enable = true;
    videoDrivers = [ "amdgpu" ];
  };

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
  };

  # Enable desktop portal
  # xdg.portal = {
  #   enable = true;
  #   wlr = {
  #     enable = true;
  #   };
  #   extraPortals = [
  #     pkgs.xdg-desktop-portal-gtk
  #     pkgs.xdg-desktop-portal-wlr
  #   ];
  #   # TODO: research <https://github.com/flatpak/xdg-desktop-portal/blob/1.18.1/doc/portals.conf.rst.in>
  #   config.common.default = "*";
  # };

  ## X11 specific
  # services.xserver = {
  #   xkb.layout = "us";
  #   xkb.variant = ",phonetic";
  #   xkb.options = "grp:lalt_lshift_toggle";
  # };

  # services.greetd = {
  #   enable = true;
  #   settings = rec {
  #     initial_session = "${pkgs.hyprland}/bin/hyprland";
  #     user = "conroy";
  #   };
  # };

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

  age.secrets."conroy.user.password" = {
    rekeyFile = "${inputs.self}/secrets/home/kombu/user/password.age";
    mode = "440";
  };

  ### Define a user account. Don't forget to set a password with `passwd`.
  users.users.conroy = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets."conroy.user.password".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB" # conroy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPwrQhUM6udasli+ypO2n7upXXB1irr2s5jJQjJdOp1w" # kombu system key
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
    # theme = lib.mkForce "breeze";
  };
  boot.initrd.systemd.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    xdg-utils
    neovim
    wget
  ];

  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    config.credential.helper = "libsecret";
  };

  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "conroy" ];
  };

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
