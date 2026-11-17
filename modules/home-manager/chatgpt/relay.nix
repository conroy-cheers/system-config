{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  relaySetups = lib.filterAttrs (_: setup: setup.enable && setup.relay.enable) cfg.profiles;
  catalogSetups = lib.filterAttrs (_: setup: setup.relay.catalog.enable) relaySetups;
  relaySettings =
    setup:
    {
      model_provider = "relay";
      web_search = "disabled";
    }
    // lib.optionalAttrs setup.relay.catalog.enable {
      model_catalog_json = setup.relay.catalog.cacheFile;
    };
  catalogPackage =
    setup:
    pkgs.writeShellApplication {
      name = "${setup.command}-relay-refresh";
      text = ''
        exec ${lib.getExe pkgs.python3} ${./refresh-relay-catalog.py} \
          --config ${
            pkgs.writeText "codex-relay-catalog.json" (
              builtins.toJSON {
                cache_file = setup.relay.catalog.cacheFile;
                codex = lib.getExe' setup.package "codex";
                client_version = setup.package.version;
                relay = lib.getExe setup.relay.package;
                api_key_file = setup.relay.apiKeyFile;
                backend = setup.relay.backend;
                routes = lib.optionals (setup.relay.backend == "cliproxyapi") (
                  setup.relay.cliProxy.nativeModels ++ setup.relay.cliProxy.chatModels
                );
                upstream =
                  if setup.relay.backend == "cliproxyapi" then
                    "http://127.0.0.1:${toString setup.relay.port}/v1"
                  else
                    setup.relay.catalog.upstream;
                strip_prefix = setup.relay.catalog.stripPrefix;
                model_template = setup.relay.catalog.modelTemplate;
                reasoning_efforts = setup.relay.catalog.reasoningEfforts;
                overrides = setup.relay.catalog.overrides;
                refresh_interval = setup.relay.catalog.refreshInterval;
                default_relay = setup.relay.makeDefault;
              }
            )
          } "$@"
      '';
    };
  relayScript =
    name: setup:
    if setup.relay.backend == "cliproxyapi" then
      pkgs.writeShellScript "codex-${name}-relay" ''
        exec ${lib.getExe pkgs.python3} ${./start-cliproxyapi.py} \
          --program ${lib.getExe setup.relay.package} \
          --template ${pkgs.writeText "codex-${name}-cliproxyapi.json" (builtins.toJSON (cliProxySettings setup))} \
          --api-key-file ${lib.escapeShellArg setup.relay.apiKeyFile}
      ''
    else
      pkgs.writeShellScript "codex-${name}-relay" ''
        set -e
        ${lib.optionalString (setup.relay.apiKeyFile != null) ''
          CODEX_RELAY_API_KEY="$(${lib.getExe' pkgs.coreutils "cat"} ${lib.escapeShellArg setup.relay.apiKeyFile})"
          export CODEX_RELAY_API_KEY
        ''}
        exec ${lib.getExe setup.relay.package} \
          --bind 127.0.0.1 \
          --port ${toString setup.relay.port} \
          --upstream ${lib.escapeShellArg setup.relay.upstream}
      '';
  cliProxySettings = setup: {
    config-version = 8;
    server = {
      host = "127.0.0.1";
      port = setup.relay.port;
    };
    management = {
      disable-control-panel = true;
      disable-auto-update-panel = true;
    };
    client.codex.enable-apply-patch = true;
    multimedia.disable-image-generation = "passthrough";
    routing.retry.request-retry = 0;
    observability.logs.error-logs-max-files = 0;
    api-keys = {
      codex = lib.optional (setup.relay.cliProxy.nativeModels != [ ]) {
        name = "native-responses";
        base-url = setup.relay.upstream;
        models = setup.relay.cliProxy.nativeModels;
        keys = [ { disable-codex-cloaking = true; } ];
      };
      openai-compatibility = lib.optional (setup.relay.cliProxy.chatModels != [ ]) {
        name = "function-tool-bridge";
        base-url = setup.relay.upstream;
        models = setup.relay.cliProxy.chatModels;
        keys = [ { } ];
      };
    };
  };
in
{
  options.programs.chatgpt.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }: {
          config = lib.mkIf (config.enable && config.relay.enable) {
            relay.launcher = relayScript name config;
            relay.catalog.refreshPackage = catalogPackage config;
            configProfiles.chat-completions = {
              settings = relaySettings config;
              removeSettings = lib.optional (!config.relay.catalog.enable) [ "model_catalog_json" ];
            };
            removeSettings = lib.optionals (config.relay.makeDefault && !config.relay.catalog.enable) [
              [ "model_catalog_json" ]
            ];
            settings = lib.mkMerge [
              {
                model_providers.relay = {
                  name =
                    if config.relay.backend == "cliproxyapi" then
                      "Selective model adapter"
                    else
                      "Chat Completions relay";
                  base_url = "http://127.0.0.1:${toString config.relay.port}/v1";
                  wire_api = "responses";
                  requires_openai_auth = false;
                  supports_websockets = false;
                };
              }
              (lib.mkIf config.relay.makeDefault (relaySettings config))
            ];
          };
        }
      )
    );
  };
  config = lib.mkIf cfg.enable {
    home.packages =
      map (s: s.relay.package) (builtins.attrValues relaySetups)
      ++ map (s: s.relay.catalog.refreshPackage) (builtins.attrValues catalogSetups);
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      (lib.mapAttrs' (
        name: setup:
        lib.nameValuePair "${setup.command}-relay" {
          Unit = {
            Description = "Local model adapter for ${name} Codex";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${setup.relay.launcher}";
            ExecStartPost = lib.optional (setup.relay.backend == "cliproxyapi") (
              "${lib.getExe pkgs.curl} --silent --show-error --fail --retry 10 --retry-connrefused --retry-delay 1 --max-time 2 --output /dev/null http://127.0.0.1:${toString setup.relay.port}/v1/models"
            );
            Restart = "on-failure";
            RestartSec = 5;
            UMask = "0077";
          };
          Install.WantedBy = [ "default.target" ];
        }
      ) relaySetups)
      // (lib.mapAttrs' (
        _: setup:
        lib.nameValuePair "${setup.command}-relay-catalog" {
          Unit = {
            Description = "Refresh ${setup.command} relay model catalog";
            After = lib.optional (setup.relay.backend == "cliproxyapi") "${setup.command}-relay.service";
            Requires = lib.optional (setup.relay.backend == "cliproxyapi") "${setup.command}-relay.service";
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe setup.relay.catalog.refreshPackage} --if-stale";
            UMask = "0077";
          };
          Install.WantedBy = lib.optional (
            setup.relay.backend == "cliproxyapi"
          ) "${setup.command}-relay.service";
        }
      ) catalogSetups)
    );
    systemd.user.timers = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mapAttrs' (
        _: setup:
        lib.nameValuePair "${setup.command}-relay-catalog" {
          Unit.Description = "Periodically refresh ${setup.command} relay model catalog";
          Timer = {
            OnActiveSec = "1m";
            OnUnitActiveSec = "${toString (lib.min 3600 setup.relay.catalog.refreshInterval)}s";
          };
          Install.WantedBy = [ "timers.target" ];
        }
      ) catalogSetups
    );
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      (lib.mapAttrs' (
        name: setup:
        lib.nameValuePair "${setup.command}-relay" {
          enable = true;
          config = {
            ProgramArguments = [ "${setup.relay.launcher}" ];
            ProcessType = "Background";
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
          };
        }
      ) relaySetups)
      // (lib.mapAttrs' (
        _: setup:
        lib.nameValuePair "${setup.command}-relay-catalog" {
          enable = true;
          config = {
            ProgramArguments = [
              (lib.getExe setup.relay.catalog.refreshPackage)
              "--if-stale"
            ];
            ProcessType = "Background";
            RunAtLoad = true;
            StartInterval = lib.min 3600 setup.relay.catalog.refreshInterval;
          };
        }
      ) catalogSetups)
    );
  };
}
