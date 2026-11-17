# Home Manager's Codex renderers take a config directory even though its public
# module hard-codes one. Supply each instance's directory to those same helpers.
{
  lib,
  pkgs,
  inputs,
  homeConfig,
}:
name: setup:
let
  upstream = "${inputs.home-manager}/modules/programs/codex";
  codexLib = import "${upstream}/lib.nix" { inherit lib pkgs; };
  toml = pkgs.formats.toml { };
  json = pkgs.formats.json { };
  configDir = setup.codexHome;
  marketplaceName = "home-manager";
  marketplaceDir = "${configDir}/plugins/home-manager-marketplace";
  cacheDir = "${configDir}/plugins/cache/${marketplaceName}";
  helpers = codexLib.mkHelpers {
    inherit configDir;
    skillsDir = "${configDir}/skills";
    pluginsCacheDir = "${configDir}/plugins/cache";
    homeRelativePluginsCacheDir = lib.removePrefix "${homeConfig.home.homeDirectory}/" "${configDir}/plugins/cache";
    pluginsMarketplaceName = marketplaceName;
    tomlFormat = toml;
  };
  mcpServers = lib.optionalAttrs (setup.enableMcpIntegration && homeConfig.programs.mcp.enable) (
    lib.mapAttrs (
      serverName: server:
      lib.hm.mcp.transformMcpServer {
        inherit server;
        exclude = [
          "headers"
          "type"
        ];
        extraTransforms = [
          (s: s // lib.optionalAttrs (s.headers or { } != { }) { http_headers = s.headers; })
          lib.hm.mcp.addType
          (lib.hm.mcp.wrapEnvFilesCommand {
            inherit pkgs;
            name = "${name}-${serverName}";
          })
        ];
      }
    ) homeConfig.programs.mcp.servers
  );
  settings = lib.recursiveUpdate (if setup.settings == null then { } else setup.settings) (
    lib.optionalAttrs (setup.plugins != [ ] || setup.marketplaces != { }) {
      features.plugins = true;
      marketplaces =
        lib.mapAttrs helpers.mkMarketplaceConfigEntry setup.marketplaces
        // lib.optionalAttrs (setup.plugins != [ ]) {
          ${marketplaceName} = {
            source_type = "local";
            source = marketplaceDir;
          };
        };
    }
  );
  mergedSettings =
    settings
    // lib.optionalAttrs (mcpServers != { }) {
      mcp_servers = mcpServers // (settings.mcp_servers or { });
    };
  # Resolve every plugin's manifest at build time with Home Manager's own
  # normalizer. This also covers fetchers and packages whose identity is unknown
  # during evaluation, without a separate implementation for those sources.
  pluginEntries = lib.imap0 (index: plugin: {
    placeholder = "__home_manager_derived_plugin_${toString index}__";
    source = toString plugin;
    fallbackName =
      if lib.isDerivation plugin then
        plugin.pname or (lib.getName plugin)
      else
        baseNameOf (toString plugin);
  }) setup.plugins;
  pluginBundle =
    pkgs.runCommandLocal "${setup.command}-plugins"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.remarshal
        ];
        passAsFile = [ "pluginSpecs" ];
        pluginSpecs = builtins.toJSON pluginEntries;
      }
      ''
        mkdir -p "$out/cache" "$out/.agents/plugins" "$out/plugins/cache"
        python3 ${upstream}/normalize-plugins.py "$pluginSpecsPath" \
          ${
            json.generate "${setup.command}-plugin-settings.json" (
              mergedSettings
              // {
                plugins =
                  (mergedSettings.plugins or { })
                  // lib.listToAttrs (
                    map (
                      entry: lib.nameValuePair "${entry.placeholder}@${marketplaceName}" { enabled = true; }
                    ) pluginEntries
                  );
              }
            )
          } \
          ${
            json.generate "${setup.command}-marketplace.json" {
              name = marketplaceName;
              interface.displayName = "Home Manager";
              plugins = map (entry: {
                name = entry.placeholder;
                source = {
                  source = "local";
                  path = entry.placeholder;
                };
                policy = {
                  installation = "AVAILABLE";
                  authentication = "ON_INSTALL";
                };
                category = "Productivity";
              }) pluginEntries;
            }
          } \
          "$out" plugins/cache ${lib.escapeShellArg marketplaceName}
        mv "$out/cache" "$out/plugins/cache/${marketplaceName}"
        mv "$out/marketplace.json" "$out/.agents/plugins/marketplace.json"
        remarshal --if json --of toml "$out/config.json" "$out/config.toml"
      '';
  hooksArePath = lib.hm.strings.isPathLike setup.hooks;
  hooks = pkgs.runCommandLocal "${setup.command}-hooks" { } ''
    source=${lib.escapeShellArg (toString setup.hooks)}
    mkdir -p "$out"
    if [[ -d "$source" && -f "$source/hooks.json" ]]; then
      ln -s "$source/hooks.json" "$out/hooks.json"
      ln -s "$source" "$out/hooks"
    elif [[ -f "$source" ]]; then
      ln -s "$source" "$out/hooks.json"
    else
      echo "Codex ${name} hooks must be a JSON file or a directory containing hooks.json" >&2
      exit 1
    fi
  '';
  skillsArePath = lib.hm.strings.isPathLike setup.skills;
  skills = pkgs.runCommandLocal "${setup.command}-skills" { } ''
    source=${lib.escapeShellArg (toString setup.skills)}
    test -d "$source"
    mkdir -p "$out/stage" "$out/normalized"
    shopt -s dotglob nullglob
    for skill in "$source"/*; do
      skill_name="''${skill##*/}"
      if [[ -d "$skill" ]]; then
        ln -s "$skill" "$out/stage/$skill_name"
      elif [[ -f "$skill" ]]; then
        mkdir -p "$out/normalized/$skill_name"
        cp "$skill" "$out/normalized/$skill_name/SKILL.md"
        ln -s "$out/normalized/$skill_name" "$out/stage/$skill_name"
      else
        echo "Codex ${name} skill '$skill' must be a file or directory" >&2
        exit 1
      fi
    done
  '';
in
{
  settingsFile =
    if setup.plugins == [ ] then
      toml.generate "${setup.command}-config.toml" mergedSettings
    else
      "${pluginBundle}/config.toml";
  files = lib.mkMerge [
    (lib.listToAttrs [ (helpers.mkTextOrPathEntry "${configDir}/AGENTS.md" setup.context) ])
    (lib.optionalAttrs (setup.contextOverride != null) (
      lib.listToAttrs [
        (helpers.mkTextOrPathEntry "${configDir}/AGENTS.override.md" setup.contextOverride)
      ]
    ))
    (lib.mapAttrs' helpers.mkRuleEntry setup.rules)
    (
      if skillsArePath then
        {
          "${configDir}/skills" = {
            source = skills + "/stage";
            recursive = true;
            ignorelinks = true;
          };
        }
      else
        lib.mapAttrs' helpers.mkSkillEntry setup.skills
    )
    (lib.optionalAttrs (setup.hooks != { }) (
      if hooksArePath then
        {
          "${configDir}" = {
            source = hooks;
            recursive = true;
          };
        }
      else
        {
          "${configDir}/hooks.json".source = json.generate "${setup.command}-hooks.json" {
            inherit (setup) hooks;
          };
        }
    ))
    (lib.optionalAttrs (setup.plugins != [ ]) {
      "${marketplaceDir}".source = pluginBundle;
      "${cacheDir}" = {
        source = "${pluginBundle}/plugins/cache/${marketplaceName}";
        recursive = true;
        ignorelinks = true;
      };
    })
  ];
  cleanPlugins = lib.optionalString (setup.plugins != [ ]) ''
    if [[ ! -v DRY_RUN ]]; then
      for plugin in ${pluginBundle}/plugins/cache/${marketplaceName}/*/*; do
        [[ -L "$plugin" ]] || continue
        relative_path="''${plugin#${pluginBundle}/plugins/cache/${marketplaceName}/}"
        path=${lib.escapeShellArg cacheDir}/"$relative_path"
        if [[ -d "$path" && ! -L "$path" ]]; then
          rm -rf -- "$path"
        fi
      done
    fi
  '';
  assertions = [
    {
      assertion = !(setup.plugins != [ ] && setup.marketplaces ? ${marketplaceName});
      message = "Codex instance ${name}: the home-manager marketplace is reserved for declared plugins.";
    }
  ];
}
