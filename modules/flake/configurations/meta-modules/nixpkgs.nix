{ config, lib, ... }:
let
  inherit (lib) types;
in
{
  options = {
    nixpkgs = {
      variant = lib.mkOption {
        description = "The Nixpkgs variant to use for this host";
        type = types.enum [
          "default"
          "withCuda"
        ];
      };
    };
  };
}
