{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  homeConfig = config;
  configHome = config.home.homeDirectory;
  xdgConfigHome = config.xdg.configHome;
  xdgCacheHome = config.xdg.cacheHome;
  codexOptions =
    (import "${inputs.home-manager}/modules/programs/codex/options.nix" {
      inherit lib pkgs;
    }).options.programs.codex;
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
            inherit (codexOptions)
              settings
              context
              contextOverride
              hooks
              skills
              rules
              plugins
              marketplaces
              enableMcpIntegration
              ;
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
              default =
                if name == "default" then
                  if homeConfig.home.preferXdgDirectories then "${xdgConfigHome}/codex" else "${configHome}/.codex"
                else
                  "${configHome}/.${config.command}";
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
              description = "The generated CLI wrapper.";
            };
            configProfiles = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    settings = mkOption {
                      type = codexOptions.profiles.type.nestedTypes.elemType;
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
              description = "Shell commands run after config merging during activation.";
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
                description = "The generated desktop launcher.";
              };
            };
          };
        }
      )
    );
  };
}
