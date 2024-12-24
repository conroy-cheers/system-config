{ inputs, lib, pkgs, config, ... }:

{
  imports = [
    inputs.wired.homeManagerModules.default
    ./conroy/op.nix
    ./conroy/ssh.nix
    ./conroy/vscode.nix
    ./conroy/wm/hyprland.nix
    ../themes/stylix.nix
  ];

  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "24.05";
  };

  stylix = {
    targets.hyprland.enable = true;
    targets.kitty.enable = true;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    ## WM
    # river
    # swww # wallpaper deamon
    # # wired-notify # dunst on wayland
    # waybar # status bar
    # xwayland
    # wl-clipboard
    # slurp # select regions from wayland
    # grim # grap images from regions
    # playerctl # music control
    gparted
    audacity
    qalculate-gtk
    libreoffice-qt6-fresh
    jujutsu

    slack
    pciutils # lspci
    usbutils # lsusb
    (uutils-coreutils.override { prefix = ""; }) # coreutils in rust

    ## Debugger
    gdb
    lttng-tools
    lttng-ust

    grimblast

    plexamp

    ## Dhall
    dhall
    # dhall-lsp-server

    ## Nix
    nil
    direnv
    nixpkgs-fmt
    nix-output-monitor

    ## Torrents
    tremc

    ## Python
    ruff

    ## Rust
    rustc
    cargo
    rust-analyzer
    clang
    openssl
    pkg-config

    ## Zig
    # zigpkgs."0.10.1"
    zigpkgs.master
    # inputs.zls-overlay.packages.x86_64-linux.default
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

  programs.kitty = {
    enable = true;
    settings = {
      scrollback_lines = 20000;
    };
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
    userName = "Conroy Cheers";
    userEmail = "conroy@dromeda.com.au";
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

  corncheese = {
    shell = {
      enable = true;
      direnv = true;
      zoxide = true;
      shells = [ "zsh" ];
    };
    wezterm = {
      enable = true;
    };
  };

  home.file = {
    ".config/nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/src/reovim";
    };
  };

  # home.file.".stack/config.yaml".text = lib.generators.toYAML {} {
  #   templates = {
  #     scm-init = "git";
  #     params = with config.programs.git; {
  #       author-name = userName;
  #       author-email = userEmail;
  #       github-username = userName;
  #     };
  #   };
  #   nix.enable = true;
  # };
}
