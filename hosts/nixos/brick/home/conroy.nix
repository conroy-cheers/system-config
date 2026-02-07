{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

{
  imports = [ inputs.wired.homeManagerModules.default ];

  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "24.05";
  };

  age.rekey = {
    hostPubkey = lib.mkForce "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICuABSLmzF3xy8AUA1tqzy11jnkubwbcVALayATZ43fL conroy@brick";
  };

  corncheese = {
    development = {
      electronics = {
        enable = true;
      };
      mechanical.enable = true;
      audio.enable = true;
      jetbrains = {
        enable = true;
        # clion.versionOverride = "2023.2.5";
      };
      rust.enable = false;
      vscode.enable = true;
      ssh = {
        enable = true;
        onePassword = true;
      };
      photo.enable = true;
    };
    scm = {
      git.enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm = {
      enable = true;
      nvidia = false;
      ags.enable = true;
      hyprpaper.enable = true;
      enableFancyEffects = true;
    };
    desktop = {
      enable = true;
      mail.enable = true;
      firefox.enable = false;
      chromium.enable = true;
      element.enable = true;
      media = {
        enable = true;
      };
    };
    shell = {
      enable = true;
      starship = true;
      p10k = false;
      direnv = true;
      zoxide = true;
      atuin = {
        enable = true;
        sync = true;
      };
      shells = [ "fish" ];
    };
    wezterm = {
      enable = true;
    };
    music = {
      enable = true;
    };
  };
  andromeda = {
    development.enable = true;
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "desc: LG Electronics 27GN950 008NTJJ7W924,3840x2160@160,0x0,1.33333,vrr,3"
      "desc: Dell Inc. DELL U2720Q 8LXMZ13,3840x2160@60,2880x0,1.33333,vrr,0"
      ",preferred,auto,1"
    ];
  };

  stylix = {
    targets.hyprland.enable = true;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    gparted
    audacity
    libreoffice-qt6-fresh

    pciutils # lspci
    usbutils # lsusb
    # (uutils-coreutils.override { prefix = ""; }) # coreutils in rust

    ## Windows
    lutris

    ## Wine
    # winetricks (all versions)
    winetricks
    # native wayland support (unstable)
    wineWowPackages.waylandFull
    samba
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  services.udiskie.enable = true;

  # Enable the GPG Agent daemon.
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  programs.vifm = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };

  programs.btop = {
    enable = true;
  };

  programs.cava = {
    enable = true;
  };

  programs.gpg = {
    enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
  xdg.configFile."nvim/init.lua".enable = false;

  home.file = {
    ".config/nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/src/reovim";
    };
  };

  programs.vesktop = {
    enable = true;
  };
}
