{
  lib,
  config,
  self,
  inputs,
  ...
}:

{
  imports = [
    ../lib
    ../things
  ];

  options =
    let
      inherit (lib) types;
      inherit (config.lib) createThings;

      createChecks =
        baseDir:
        createThings {
          inherit baseDir;
          thingType = "check";
          raw = false;
          extras.systems = {
            default = lib.const true;
          };
        };
    in
    {
      auto.checks = lib.mkOption {
        description = ''
          Automagically generate checks from walking directories with Nix files
        '';
        type = types.submodule (submodule: {
          options = {
            enable = lib.mkEnableOption "Automatic checks extraction";
            dir = lib.mkOption {
              description = ''
                Base directory of the contained checks
              '';
              type = types.path;
              default = "${self}/tests/nixos";
              defaultText = "\${self}/tests/nixos";
            };
            result = lib.mkOption {
              description = ''
                The resulting automatic checks
              '';
              type = types.attrsOf (
                types.submodule {
                  options = {
                    check = lib.mkOption { type = types.unspecified; };
                    systems = lib.mkOption { type = types.functionTo types.bool; };
                  };
                }
              );
              readOnly = true;
              internal = true;
              default = lib.optionalAttrs config.auto.checks.enable (createChecks config.auto.checks.dir);
            };
          };
        });
        default = { };
      };
    };

  config = {
    perSystem =
      {
        lib,
        pkgs,
        system,
        ...
      }@perSystemArgs:
      let
        checks = lib.pipe config.auto.checks.result [
          (lib.filterAttrs (name: { systems, ... }: pkgs.default.callPackage systems { inherit inputs; }))
          (lib.mapAttrs (
            name:
            { check, ... }:
            pkgs.default.callPackage check {
              inherit inputs;
              inherit (perSystemArgs) config system;
            }
          ))
        ];
      in
      {
        inherit checks;
      };
  };
}
