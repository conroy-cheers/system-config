{ inputs, pkgs, ... }:

{
  imports = [ inputs.wired.homeManagerModules.default ];

  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "25.11";
  };

  corncheese = {
    development = {
      enable = false;
      electronics.enable = false;
      mechanical.enable = false;
      audio.enable = false;
      jetbrains.enable = false;
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
      atuin.enable = false;
      shells = [ "fish" ];
    };
  };

  programs.home-manager.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
  programs.ripgrep.enable = true;
  programs.btop.enable = true;

  home.packages = with pkgs; [ ];
}
