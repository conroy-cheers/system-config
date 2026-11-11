{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.programs.chatgpt;
  configHome = config.home.homeDirectory;
  xdgConfigHome = config.xdg.configHome;
  xdgCacheHome = config.xdg.cacheHome;
  toml = pkgs.formats.toml { };
  setups = lib.filterAttrs (_: setup: setup.enable) cfg.profiles;
  desktopSetups = lib.filterAttrs (_: setup: setup.desktop.enable) setups;
  relaySetups = lib.filterAttrs (_: setup: setup.relay.enable) setups;
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
  mergePython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
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
  mergeScript =
    name: setup:
    pkgs.writeShellScript "merge-codex-${name}-config" ''
      set -e
      ${mergePython}/bin/python ${./merge-config.py} \
        ${toml.generate "codex-${name}.toml" setup.settings} \
        ${lib.escapeShellArg "${setup.codexHome}/config.toml"} \
        ${lib.escapeShellArg (builtins.toJSON setup.removeSettings)}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (profileName: profile: ''
          ${mergePython}/bin/python ${./merge-config.py} \
            ${toml.generate "codex-${name}-${profileName}.toml" profile.settings} \
            ${lib.escapeShellArg "${setup.codexHome}/${profileName}.config.toml"} \
            ${lib.escapeShellArg (builtins.toJSON profile.removeSettings)}
        '') setup.configProfiles
      )}
      ${setup.afterMerge}
      ${lib.optionalString
        (setup.relay.enable && setup.relay.catalog.enable && setup.relay.backend == "codex-relay")
        ''
          ${lib.getExe setup.relay.catalog.refreshPackage} --if-stale --allow-missing
        ''
      }
    '';
  cliPackage =
    name: setup:
    pkgs.symlinkJoin {
      name = "${setup.command}-wrapped";
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
  desktopPackage =
    name: setup:
    pkgs.runCommand setup.desktop.command
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = setup.desktop.command;
      }
      ''
        mkdir -p "$out/bin" "$out/share/icons"
        ln -s ${setup.desktop.package}/share/icons/hicolor "$out/share/icons/hicolor"
        makeWrapper ${lib.getExe' setup.desktop.package "codex-desktop"} \
          "$out/bin/${setup.desktop.command}" \
          --set CODEX_CLI_PATH ${lib.escapeShellArg (lib.getExe setup.finalPackage)} \
          --set CODEX_HOME ${lib.escapeShellArg setup.codexHome} \
          --set CODEX_APP_ID ${lib.escapeShellArg setup.desktop.appId} \
          --set CODEX_LINUX_APP_ID ${lib.escapeShellArg setup.desktop.appId} \
          --set CODEX_LINUX_APP_DISPLAY_NAME ${lib.escapeShellArg setup.desktop.name} \
          --set CODEX_ELECTRON_USER_DATA_PATH ${lib.escapeShellArg setup.desktop.userDataDir} \
          --set CODEX_WEBVIEW_PORT ${toString setup.desktop.webviewPort} \
          --set CHROME_DESKTOP ${lib.escapeShellArg "${setup.desktop.appId}.desktop"} \
          --set BAMF_DESKTOP_FILE_HINT ${lib.escapeShellArg "${config.xdg.dataHome}/applications/${setup.desktop.appId}.desktop"} \
          --run ${
            lib.escapeShellArg (
              lib.optionalString (
                setup.relay.enable && setup.relay.catalog.enable
              ) "${lib.getExe setup.relay.catalog.refreshPackage} --if-stale --allow-missing"
            )
          } \
          --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p ${
            lib.escapeShellArgs [
              setup.codexHome
              setup.desktop.userDataDir
            ]
          }"}
      '';
  unique = values: builtins.length values == builtins.length (lib.unique values);
  valuesOf = f: attrs: map f (builtins.attrValues attrs);
in
{
  options.programs.chatgpt.enable = lib.mkEnableOption "ChatGPT and Codex profiles";
  options.programs.chatgpt.profiles = mkOption {
    default = { };
    description = ''
      Named ChatGPT and Codex profiles with optional desktop launchers sharing
      the same Codex configuration. Mutable app settings are preserved when
      Nix-managed settings are merged into each config.toml. Enabling the
      module creates a default profile for the regular codex command.
    '';
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }: {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };
            command = mkOption {
              type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9._-]*";
              default = if name == "default" then "codex" else "codex-${name}";
              description = "CLI command installed for this setup.";
            };
            codexHome = mkOption {
              type = types.str;
              default = "${configHome}/.${config.command}";
              description = "Absolute mutable CODEX_HOME directory for CLI and desktop.";
            };
            package = mkOption {
              type = types.package;
              default = inputs.codex-flake.packages.${pkgs.stdenv.hostPlatform.system}.codex;
              description = "Unwrapped package providing bin/codex.";
            };
            finalPackage = mkOption {
              type = types.package;
              readOnly = true;
              default = cliPackage name config;
              description = "The generated CLI wrapper.";
            };
            settings = mkOption {
              type = toml.type;
              default = { };
            };
            configProfiles = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    settings = mkOption {
                      type = toml.type;
                      default = { };
                    };
                    removeSettings = mkOption {
                      type = types.listOf (types.listOf types.str);
                      default = [ ];
                      description = "Obsolete managed paths to remove from this profile.";
                    };
                  };
                }
              );
              default = { };
              description = "Managed settings merged into mutable <name>.config.toml files. Unmanaged settings such as the selected model are preserved.";
            };
            removeSettings = mkOption {
              type = types.listOf (types.listOf types.str);
              default = [ ];
              example = [
                [
                  "mcp_servers"
                  "slack"
                ]
              ];
              description = "Paths to obsolete managed settings to remove during merging.";
            };
            extraPackages = mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Additional tools added to this CLI's PATH alongside the standard search, archive, and HTTP tools.";
            };
            beforeLaunch = mkOption {
              type = types.lines;
              default = "";
              description = "Shell commands run before CLI launch; arguments are available in $@.";
            };
            afterMerge = mkOption {
              type = types.lines;
              default = "";
              description = "Shell commands run after config merging at activation and login.";
            };
            activationScript = mkOption {
              type = types.lines;
              default = "";
              description = "Shell commands run only during activation, after config merging.";
            };
            relay = {
              enable = lib.mkEnableOption "a local model adapter for this Codex setup";
              makeDefault = lib.mkEnableOption "the relay provider and catalog as this setup's defaults";
              backend = mkOption {
                type = types.enum [
                  "codex-relay"
                  "cliproxyapi"
                ];
                default = "codex-relay";
                description = "Local adapter: a Chat Completions bridge or selective native Responses/tool conversion.";
              };
              package = mkOption {
                type = types.package;
                default = if config.relay.backend == "cliproxyapi" then pkgs.cliproxyapi else pkgs.codex-relay;
                description = "Package providing the selected relay backend.";
              };
              launcher = mkOption {
                type = types.package;
                readOnly = true;
                default = relayScript name config;
                description = "Runtime launcher for the selected adapter, including private credential setup.";
              };
              cliProxy = {
                nativeModels = mkOption {
                  type = types.listOf (types.attrsOf (pkgs.formats.json { }).type);
                  default = [ ];
                  description = "CLIProxyAPI model mappings routed through native Responses. Each has name, alias and optional thinking metadata.";
                };
                chatModels = mkOption {
                  type = types.listOf (types.attrsOf (pkgs.formats.json { }).type);
                  default = [ ];
                  description = "CLIProxyAPI model mappings routed through Chat Completions with custom-tool conversion.";
                };
              };
              port = mkOption {
                type = types.port;
                default = 4444;
                description = "Unique loopback port for this setup's relay.";
              };
              upstream = mkOption {
                type = types.str;
                example = "https://gateway.example/openai/v1/";
                description = "Upstream API base URL. CLIProxyAPI uses both Responses and Chat Completions beneath it.";
              };
              apiKeyFile = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Runtime file containing the upstream bearer token; never copied to the Nix store.";
              };
              catalog = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Cache a version-validated model catalog for the adapter at runtime.";
                };
                upstream = mkOption {
                  type = types.str;
                  default = config.relay.upstream;
                  description = "Discovery API base URL for codex-relay; /models is appended. CLIProxyAPI uses its local Codex catalog instead.";
                };
                stripPrefix = mkOption {
                  type = types.str;
                  default = "";
                  description = "Only include model IDs with this prefix and remove it for passthrough inference.";
                };
                modelTemplate = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Bundled Codex model whose instructions and tool formats the relay generator should use.";
                };
                overrides = mkOption {
                  type = types.attrsOf (types.attrsOf (pkgs.formats.json { }).type);
                  default = { };
                  example = {
                    "example-model".context_window = 131072;
                  };
                  description = "Metadata overrides keyed by normalized model ID. Model slugs cannot be changed.";
                };
                reasoningEfforts = mkOption {
                  type = types.nullOr (types.listOf types.str);
                  default = null;
                  example = [
                    "low"
                    "medium"
                    "high"
                    "xhigh"
                  ];
                  description = "Restrict catalog reasoning levels to efforts accepted by this gateway. Null preserves the model's levels; per-model overrides take precedence.";
                };
                refreshInterval = mkOption {
                  type = types.ints.positive;
                  default = 86400;
                  description = "Maximum catalog age in seconds before refreshing. Failed attempts have a five-minute retry backoff.";
                };
                cacheFile = mkOption {
                  type = types.str;
                  default = "${xdgCacheHome}/${config.command}/relay/models.json";
                  description = "Absolute path to the runtime catalog cache.";
                };
                refreshPackage = mkOption {
                  type = types.package;
                  readOnly = true;
                  default = catalogPackage config;
                  description = "The generated per-instance catalog refresh command.";
                };
              };
            };
            desktop = {
              enable = lib.mkEnableOption "a ChatGPT desktop launcher for this setup";
              package = mkOption {
                type = types.package;
                default = inputs.codex-desktop-linux.packages.${pkgs.stdenv.hostPlatform.system}.default;
                description = "Desktop package providing bin/codex-desktop.";
              };
              command = mkOption {
                type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9._-]*";
                default = config.desktop.appId;
              };
              appId = mkOption {
                type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9._-]*";
                default = "codex-desktop${lib.optionalString (name != "default") "-${name}"}";
              };
              name = mkOption {
                type = types.str;
                default = "ChatGPT${lib.optionalString (name != "default") " (${name})"}";
              };
              userDataDir = mkOption {
                type = types.str;
                default = "${xdgConfigHome}/${if name == "default" then "Codex" else config.desktop.appId}";
                description = "Separate Electron profile; the default setup preserves the existing Codex profile.";
              };
              webviewPort = mkOption {
                type = types.port;
                description = "Unique webview port for this desktop setup.";
              };
              finalPackage = mkOption {
                type = types.package;
                readOnly = true;
                default = desktopPackage name config;
                description = "The generated desktop launcher.";
              };
            };
          };
          config = lib.mkIf (config.enable && config.relay.enable) {
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

    home.packages =
      (valuesOf (s: s.finalPackage) setups)
      ++ (valuesOf (s: s.desktop.finalPackage) desktopSetups)
      ++ (valuesOf (s: s.relay.package) relaySetups)
      ++ (valuesOf (s: s.relay.catalog.refreshPackage) catalogSetups);
    home.activation = lib.mapAttrs' (
      name: setup:
      lib.nameValuePair "mergeCodexSetup-${name}" (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          ${mergeScript name setup}
          ${setup.activationScript}
        ''
      )
    ) setups;
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      (lib.mapAttrs' (
        name: setup:
        lib.nameValuePair "${setup.command}-config-merge" {
          Unit = {
            Description = "Merge ${name} Codex configuration";
            After = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${mergeScript name setup}";
            RemainAfterExit = true;
          };
          Install.WantedBy = [ "default.target" ];
        }
      ) setups)
      // (lib.mapAttrs' (
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
        lib.nameValuePair "${setup.command}-config-merge" {
          enable = true;
          config = {
            ProgramArguments = [ "${mergeScript name setup}" ];
            ProcessType = "Background";
            RunAtLoad = true;
          };
        }
      ) setups)
      // (lib.mapAttrs' (
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
    xdg.desktopEntries = lib.mapAttrs' (
      _: setup:
      lib.nameValuePair setup.desktop.appId {
        name = setup.desktop.name;
        genericName = "AI assistant";
        exec = "${lib.getExe setup.desktop.finalPackage} %U";
        icon = "codex-desktop";
        terminal = false;
        categories = [ "Development" ];
        mimeType = lib.optionals (setup.command == "codex") [
          "x-scheme-handler/codex"
          "x-scheme-handler/codex-browser-sidebar"
        ];
        settings.StartupWMClass = setup.desktop.appId;
      }
    ) desktopSetups;
  };
}
