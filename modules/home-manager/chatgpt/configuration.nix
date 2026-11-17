{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  setups = lib.filterAttrs (_: setup: setup.enable) cfg.profiles;
  toml = pkgs.formats.toml { };
  merger = import ./config-merge.nix { inherit lib pkgs; };
  render = import ./codex-instance.nix {
    inherit lib pkgs inputs;
    homeConfig = config;
  };
  instances = lib.mapAttrs render setups;
in
{
  config = lib.mkIf cfg.enable {
    assertions = lib.concatMap (instance: instance.assertions) (builtins.attrValues instances) ++ [
      {
        assertion = !config.programs.codex.enable;
        message = "Configure Codex through programs.chatgpt.profiles.<name>, including default, instead of enabling programs.codex alongside it.";
      }
    ];
    home.file = lib.mkMerge (map (instance: instance.files) (builtins.attrValues instances));
    home.activation =
      lib.mapAttrs' (
        name: setup:
        lib.nameValuePair "mergeCodexSetup-${name}" (
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            ${merger.merge {
              source = instances.${name}.settingsFile;
              target = "${setup.codexHome}/config.toml";
              inherit (setup) removeSettings;
            }}
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                profileName: profile:
                merger.merge {
                  source = toml.generate "${setup.command}-${profileName}.toml" profile.settings;
                  target = "${setup.codexHome}/${profileName}.config.toml";
                  inherit (profile) removeSettings;
                }
              ) setup.configProfiles
            )}
            if [[ ! -v DRY_RUN ]]; then
              ${setup.afterMerge}
              ${lib.optionalString
                (setup.relay.enable && setup.relay.catalog.enable && setup.relay.backend == "codex-relay")
                ''
                  run ${lib.getExe setup.relay.catalog.refreshPackage} --if-stale --allow-missing
                ''
              }
              ${setup.activationScript}
              :
            fi
          ''
        )
      ) setups
      // lib.mapAttrs' (
        name: instance:
        lib.nameValuePair "cleanCodexPlugins-${name}" (
          lib.hm.dag.entryBefore [ "linkGeneration" ] instance.cleanPlugins
        )
      ) (lib.filterAttrs (name: _: setups.${name}.plugins != [ ]) instances);
  };
}
