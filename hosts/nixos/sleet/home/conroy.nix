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
    shell = {
      enable = true;
      direnv = true;
      zoxide = true;
      atuin = {
        enable = true;
        sync = true;
      };
      shells = [ "zsh" ];
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
