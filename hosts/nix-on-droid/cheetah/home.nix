{ inputs, lib, pkgs, config, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = "nix-on-droid";
    # username = "corncheese";
    homeDirectory = "/data/data/com.termux.nix/files/home";
    stateVersion = "23.05";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # neovim
    # clang
    gcc

    openssh
    diffutils
    findutils
    utillinux
    tzdata
    hostname
    man
    ncurses
    gnugrep
    gnupg
    gnused
    gnutar
    bzip2
    gzip
    xz
    zip
    unzip

    direnv
    nix-direnv

    # Bling
    onefetch
    neofetch

    # Utils
    ripgrep
    duf

    # Passwords
    (pass.withExtensions (extensions: with extensions; [
      pass-otp
    ]))

    # Dhall
    # dhall
    # dhall-lsp-server

    # Emacs
    # emacs

    #
    # j
  ];

  programs.neovim = {
    enable = true;
    package = pkgs.neovim;
    # defaultEditor = true;

    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = false;
    withNodeJs = false;
    withRuby = false;

    # neovimRcContent = "";

    extraPackages = with pkgs; [
      tree-sitter
      luajitPackages.lua
      # rnix-lsp
      # sumneko-lua-language-server
      # stylua
      # texlab
      # rust-analyzer
    ];
  };

  corncheese.shell = {
    enable = true;
    username = "corncheese";
    hostname = "cheetah";
    atuin = true;
    direnv = true;
    zoxide = true;
  };

  home.file = {
    ".config/nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/src/reovim";
    };
  };

  programs.git = {
    enable = true;
    userName = "corncheese";
    userEmail = "pavel.atanasov2001@gmail.com";
    signing = {
      signByDefault = true;
      key = "675AA7EF13964ACB";
    };
  };

  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 86400;
    maxCacheTtl = 86400;
    pinentryPackage = pkgs.pinentry-tty;
    enableSshSupport = true;
    sshKeys = [ "CFDE97EDC2FDB2FD27020A084F1E3F40221BAFE7" ];
  };

  home.sessionVariables."PASSWORD_STORE_DIR" = "${config.xdg.dataHome}/password-store";
}
