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
    stateVersion = "25.05";
  };

  corncheese = {
    development = {
      enable = true;
      electronics.enable = false;
      mechanical.enable = false;
      audio.enable = false;
      jetbrains = {
        enable = false;
      };
      rust.enable = false;
      vscode.enable = false;
      ssh.enable = false;
      ssh.onePassword = false;
      ssh.zellij.enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
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
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [ ];

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

  programs.gpg = {
    enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
}
