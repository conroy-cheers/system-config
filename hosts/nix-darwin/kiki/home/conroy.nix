{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

{
  imports = [ ];

  config = {
    home = {
      username = "conroy";
      homeDirectory = "/Users/conroy";
      stateVersion = "25.11";
    };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    age.rekey = {
      hostPubkey = lib.mkForce "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPiqaH6fb+jnt0wz/s67UARLes+tvvHbVCUC29gYEClC conroy@kiki.local";
    };

    # log conroy into atuin sync
    age.secrets."corncheese.atuin.key" = {
      rekeyFile = lib.repoSecret "corncheese/atuin/key.age";
    };

    corncheese = {
      macos = {
        enable = true;
      };
      development = {
        vscode.enable = true;
        ssh.enable = true;
      };
      scm = {
        git.enable = true;
      };
      theming = {
        enable = true;
        theme = "catppuccin";
        themeOverrides = {
          opacity = lib.mkForce 0.87;
        };
      };
      desktop = {
        enable = true;
        firefox.enable = true;
        element.enable = true;
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
          key = config.age.secrets."corncheese.atuin.key".path;
        };
        shells = [ "fish" ];
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
      nixfmt-rfc-style

      teams
    ];

    programs.btop = {
      enable = true;
    };

    programs.kitty = {
      enable = true;
      settings = {
        scrollback_lines = 20000;
        background_blur = 64;
      };
    };

    programs.vscode.profiles.default.userSettings =
      let
        ptToPx = 1.0;
      in
      with config.stylix.fonts;
      {
        "editor.fontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
        "debug.console.fontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
        "markdown.preview.fontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
        "terminal.integrated.fontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
        "chat.editor.fontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
        "scm.inputFontSize" = lib.mkForce (builtins.floor (sizes.terminal * ptToPx * 13 / 14 + 0.5));
      };

    programs.ghostty.settings =
      let
        ptToPx = 1.0;
      in
      with config.stylix.fonts;
      {
        font-size = lib.mkForce (builtins.floor (sizes.terminal * ptToPx + 0.5));
      };
  };
}
