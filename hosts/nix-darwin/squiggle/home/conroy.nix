{ inputs, lib, pkgs, config, ... }:

{
  home = {
    username = "conroy";
    homeDirectory = "/Users/conroy";
    stateVersion = "24.11";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

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
      enable = false;
    };
    shell = {
      enable = true;
      direnv = true;
      zoxide = true;
      shells = [ "zsh" ];
    };
    wezterm = {
      enable = false;
    };
  };
  andromeda = {
    development.enable = true;
  };

  home.packages = with pkgs; [
    # Nix
    nil
  ];

  programs.git = {
    enable = true;
    lfs.enable = true;
    userName = "Conroy Cheers";
    userEmail = "conroy@corncheese.org";
    delta = {
      enable = true;
    };
  };

  # services.gpg-agent = {
  #   enable = true;
  #   defaultCacheTtl = 1800;
  #   enableSshSupport = true;
  # };

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
