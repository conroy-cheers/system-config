{ inputs, lib, pkgs, config, ... }:

{
  imports = [
  ];

  config = {
    home = {
      username = "conroy";
      homeDirectory = "/Users/conroy";
      stateVersion = "24.11";
    };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;

    age.rekey = {
      hostPubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDU5KdbGzMPf1R7YOyl7D/zY6UeuCFASsrX20HkGgrLRY9rBC7padJagOu1GMmd/9Bc6ZB30L/7UE/jpO345YRZlLWGsdQFcAxgGvEACixxSpUDcMUmlfmQuAmG/kWcM5LUt301iMgC+GSdiydETbJKKOnIxxz0+/wZoQB031dz7T+VvTzcoxgbNvu2GGkYZSOUyf2u9Xkj3v81/Qfc2IAbqGNWOVl/8HHWf+oyFPFJhoAd0K+tMFlxcBYe15xQsjGFA6i8fbFor3FsynY0vEn3GVWvcsErKWBHbRmLh1tHNVRc3YVewk6yM8SBiszUNQQmrMDpSI123OPOgLTbWrTh57tqPS1evHluC13GvbsMHpmizZDPcaLsOqsX9cWvLdBzLt5MrlHi3BVO58tbD4UJt4scRYqYH7yCrUKOwg/hIeOo7uvZK6pjzqSmip+mBzc1STlPoa9CNlXMydZvxr/stYWsOJohkZMbRNYl22AiJXxktFeeDJVS3yHGdKhLZr0= conroy@squiggle";
    };

    # log conroy into atuin sync
    age.secrets."corncheese.atuin.key" = {
      rekeyFile = "${inputs.self}/secrets/corncheese/atuin/key.age";
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
        enable = false;
      };
      shell = {
        enable = true;
        atuin = {
          enable = true;
          sync = true;
          key = config.age.secrets."corncheese.atuin.key".path;
        };
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
      nixfmt-rfc-style
    ];

    programs.btop = {
      enable = true;
    };

    programs.git = {
      enable = true;
      lfs.enable = true;
      userName = "Conroy Cheers";
      userEmail = "conroy@corncheese.org";
      delta = {
        enable = true;
      };
    };

    programs.kitty = {
      enable = true;
      settings = {
        scrollback_lines = 20000;
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
  };
}
