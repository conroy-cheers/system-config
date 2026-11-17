{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  setups = lib.filterAttrs (_: setup: setup.enable) cfg.profiles;
  desktopSetups = lib.filterAttrs (_: setup: setup.desktop.enable) setups;
  relaySetups = lib.filterAttrs (_: setup: setup.relay.enable) setups;
  catalogSetups = lib.filterAttrs (_: setup: setup.relay.catalog.enable) relaySetups;
  commonPackages = with pkgs; [
    ripgrep
    fd
    gnused
    gawk
    jq
    curl
    wget2
    gnutar
    unzip
    just
  ];
  cliPackage =
    setup:
    pkgs.symlinkJoin {
      name = "${setup.command}-wrapped";
      version = lib.getVersion setup.package;
      paths = [ setup.package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        ${lib.optionalString (setup.command != "codex") ''
          mv "$out/bin/codex" "$out/bin/${setup.command}"
        ''}
        wrapProgram "$out/bin/${setup.command}" \
          --argv0 codex \
          --set CODEX_HOME ${lib.escapeShellArg setup.codexHome} \
          --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg setup.codexHome}"} \
          --run ${
            lib.escapeShellArg (
              lib.optionalString (
                setup.relay.enable && setup.relay.catalog.enable
              ) ''${lib.getExe setup.relay.catalog.refreshPackage} --if-stale --for-codex "$@" || exit $?''
            )
          } \
          --run ${lib.escapeShellArg setup.beforeLaunch} \
          --prefix PATH : ${lib.escapeShellArg (lib.makeBinPath (commonPackages ++ setup.extraPackages))}
      '';
      meta.mainProgram = setup.command;
    };
  unique = values: builtins.length values == builtins.length (lib.unique values);
  valuesOf = f: attrs: map f (builtins.attrValues attrs);
in
{
  imports = [
    ./options.nix
    ./configuration.nix
    ./relay.nix
    ./desktop.nix
  ];

  options.programs.chatgpt.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          config.finalPackage = cliPackage config;
        }
      )
    );
  };

  config = lib.mkIf cfg.enable {
    programs.chatgpt.profiles.default = lib.mkDefault { };
    assertions = [
      {
        assertion = unique (valuesOf (s: s.codexHome) setups);
        message = "Codex setups must use distinct codexHome directories.";
      }
      {
        assertion = unique (
          (valuesOf (s: s.command) setups) ++ (valuesOf (s: s.desktop.command) desktopSetups)
        );
        message = "Codex CLI and desktop commands must be unique.";
      }
      {
        assertion = unique (valuesOf (s: s.desktop.appId) desktopSetups);
        message = "Codex desktop app IDs must be unique.";
      }
      {
        assertion = unique (valuesOf (s: s.desktop.userDataDir) desktopSetups);
        message = "Codex desktop user data directories must be unique.";
      }
      {
        assertion = unique (valuesOf (s: s.desktop.webviewPort) desktopSetups);
        message = "Codex desktop webview ports must be unique.";
      }
      {
        assertion = unique (valuesOf (s: s.relay.port) relaySetups);
        message = "Codex relay ports must be unique.";
      }
      {
        assertion = unique (valuesOf (s: s.relay.catalog.cacheFile) catalogSetups);
        message = "Codex relay catalog caches must use distinct files.";
      }
      {
        assertion = desktopSetups == { } || pkgs.stdenv.hostPlatform.isLinux;
        message = "Codex setup desktop launchers are only supported on Linux.";
      }
    ]
    ++ lib.mapAttrsToList (name: setup: {
      assertion =
        setup.relay.backend != "cliproxyapi"
        || (
          setup.relay.apiKeyFile != null
          && setup.relay.cliProxy.nativeModels ++ setup.relay.cliProxy.chatModels != [ ]
        );
      message = "CLIProxyAPI setup ${name} requires a runtime API key file and explicit model routes.";
    }) relaySetups
    ++ lib.mapAttrsToList (name: setup: {
      assertion =
        builtins.match "[a-zA-Z0-9][a-zA-Z0-9._-]*" name != null
        && builtins.all (profileName: builtins.match "[a-zA-Z0-9_-]+" profileName != null) (
          builtins.attrNames setup.configProfiles
        )
        && lib.hasPrefix "/" setup.codexHome
        && (
          !setup.relay.enable
          || !setup.relay.catalog.enable
          || lib.hasPrefix "/" setup.relay.catalog.cacheFile
        )
        && (!setup.desktop.enable || lib.hasPrefix "/" setup.desktop.userDataDir);
      message = "Codex setup ${name} requires a safe name and absolute home/profile paths.";
    }) setups;

    home.packages = valuesOf (s: s.finalPackage) setups;
  };
}
