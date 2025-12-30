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
      git = {
        enable = mkEnableOption "corncheese git setup";
      };
    };
  };

  config =
    let
      name = "Conroy Cheers";
      email = "conroy@corncheese.org";
      key = "29AFB8ECA82AD2FB";
    in
    {
      home.packages =
        with pkgs;
        builtins.concatLists [
          (optionals cfg.git.enable [ git ])
        ];

      programs.git = mkIf cfg.git.enable {
        enable = true;
        settings = {
          user = {
            inherit name email;
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
          signByDefault = false;
          inherit key;
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
