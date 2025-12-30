{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.corncheese.scm;

  inherit (lib)
    mkEnableOption
    types
    mkIf
    optionals
    mkMerge
    ;
in
{
  imports = [ ];

  options = {
    corncheese.scm = {
      name = lib.mkOption {
        description = "Committer name";
        type = types.str;
        default = "Conroy Cheers";
      };
      email = lib.mkOption {
        description = "User email";
        type = types.str;
        default = "conroy@corncheese.org";
      };
      key = lib.mkOption {
        description = "Fingerprint of signing key";
        type = types.str;
        default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPZ1tIiV5eVx2rk69A6k2WXpIz6HTdjjtxrql2Z4/B1s";
      };
      git = {
        enable = mkEnableOption "corncheese git setup";
      };
    };
  };

  config = {
    home.packages =
      with pkgs;
      builtins.concatLists [
        (optionals cfg.git.enable [ git ])
      ];

    programs.git = mkIf cfg.git.enable {
      enable = true;
      settings = {
        user = {
          inherit (cfg) name email;
        };
        init.defaultBranch = "master";
        url = {
          "ssh://git@github.com/" = {
            insteadOf = [
              "https://github.com/"
            ];
          };
        };
      };
      signing = {
        format = "ssh";
        signByDefault = true;
        signer = lib.getExe' pkgs._1password-gui "op-ssh-sign";
        inherit (cfg) key;
      };
      lfs = {
        enable = true;
      };
    };

    programs.delta = {
      enable = true;
      enableGitIntegration = true;
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
