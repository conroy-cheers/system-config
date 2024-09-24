{ inputs, lib, pkgs, config, ... }:

{
  imports = [
    # inputs.stylix.nixosModules.stylix
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

    ## Terminals
    # wezterm
    # foot
    kitty

    ## Core
    neovim
    git
    gnupg
    firefox
    discord
    slack
    armcord # modded discord
    vifm # file editor
    pciutils # lspci
    usbutils # lsusb
    (uutils-coreutils.override { prefix = ""; }) # coreutils in rust

    btop
    cava
    grimblast

    plexamp

    ## Shell
    # zsh
    # starship
    # zoxide
    ripgrep

    ## Dhall
    dhall
    # dhall-lsp-server

    ## Nix
    nil
    direnv

    ## Torrents
    tremc

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

  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Conroy Cheers";
    userEmail = "conroy@dromeda.com.au";
  };

  reo101 = {
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
