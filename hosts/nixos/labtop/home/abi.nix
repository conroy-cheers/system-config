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
    username = "abi";
    homeDirectory = "/home/abi";
    stateVersion = "24.05";
  };

  corncheese = {
    development = {
      vscode.enable = true;
      ssh.enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm = {
      enable = true;
      ags.enable = true;
      hyprpaper.enable = true;
    };
    shell = {
      enable = true;
      direnv = true;
      zoxide = true;
      shells = [ "zsh" ];
    };
  };
  andromeda = {
    development.enable = true;
  };

  stylix = {
    targets.hyprland.enable = true;
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "eDP-1,3072x1920@120,0x0,1.5"
      ",preferred,auto,1"
    ];
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    audacity
    qalculate-gtk
    libreoffice-qt6-fresh

    pciutils # lspci
    usbutils # lsusb
    (uutils-coreutils.override { prefix = ""; }) # coreutils in rust

    ## Debugger
    gdb
    lttng-tools
    lttng-ust

    grimblast

    ## Nix
    nil

    ## Python
    ruff

    ## Rust
    rustc
    cargo
    rust-analyzer
    clang
    openssl
    pkg-config
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

  programs.firefox = {
    enable = true;
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

  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Abi Andromeda";
    userEmail = "anyone@dromeda.com.au";
    delta = {
      enable = true;
    };
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
}
