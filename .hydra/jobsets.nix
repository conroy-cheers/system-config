{ declInput, nixpkgs, ... }:
let
  pkgs = import nixpkgs { };
in
{
  jobsets = pkgs.writeText "system-config-hydra-jobsets.json" (
    builtins.toJSON {
      main = {
        enabled = 1;
        hidden = false;
        type = 1;
        flake = "git+https://github.com/conroy-cheers/system-config?ref=main";
        description = "Builds conroy-cheers/system-config via flake hydraJobs";
        checkinterval = 300;
        schedulingshares = 100;
        enableemail = false;
        emailoverride = "";
        keepnr = 20;
        inputs = { };
      };
    }
  );
}
