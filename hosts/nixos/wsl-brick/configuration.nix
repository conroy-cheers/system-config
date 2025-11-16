# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  networking.hostName = "wsl-brick"; # Define your hostname.

  wsl = {
    enable = true;
    defaultUser = "conroy";
    useWindowsDriver = true;
    wslConf.interop.appendWindowsPath = false;
    usbip = {
      enable = true;
    };
  };

  ### Set your time zone.
  time.timeZone = "Australia/Melbourne";

  corncheese = {
    development = {
      enable = true;
      remoteBuilders.enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
  };

  andromeda = {
    development = {
      enable = true;
      tailscale.enable = false;
      remoteBuilders.enable = true;
    };
  };

  # log conroy into atuin sync
  age.secrets."corncheese.atuin.key" = {
    rekeyFile = lib.repoSecret "corncheese/atuin/key.age";
    owner = "conroy";
    mode = "0400";
  };
  home-manager.users.conroy = {
    corncheese = {
      shell.atuin = {
        key = config.age.secrets."corncheese.atuin.key".path;
      };
    };
  };

  nix = {
    settings = {
      trusted-users = [ "conroy" ];
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
        users = [ "conroy" ];
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

  # hardware.nvidia.open = true;
  # https://github.com/nix-community/NixOS-WSL/issues/454
  environment.sessionVariables = {
    LD_LIBRARY_PATH = [ "/run/opengl-driver/lib/" ];
    GALLIUM_DRIVER = "d3d12";
  };

  ### Audio (via WSLg)
  hardware.pulseaudio = {
    enable = true;
  };

  ### Wayland specific
  services.xserver = {
    enable = false; # disable xserver
    # videoDrivers = [ "nvidia" ];
  };

  ### Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.dbus = {
    enable = true;
    packages = [ pkgs.dconf ];
  };

  age.secrets."conroy.user.password" = {
    rekeyFile = lib.repoSecret "home/conroy/user/password.age";
    mode = "440";
  };

  ### Define a user account. Don't forget to set a password with `passwd`.
  users.users.conroy = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets."conroy.user.password".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvtQAUGvh3UmjM7blBM86VItgYD+22HYKzCBrXDsFGB" # conroy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUE2OxmW9PcRNvSY6wXsaxxoXNeRSYM2wj4UXR/pcW/" # brick system key
    ];
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
      "plugdev"
    ];
  };

  programs.zsh = {
    enable = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    neovim
    wget
  ];

  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    config = {
      credential.helper = "libsecret";
    };
  };

  services.ollama = {
    enable = false;
    host = "0.0.0.0";
    port = 11434;
    acceleration = "cuda";
  };

  # Firewall not necessary on WSL2
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
