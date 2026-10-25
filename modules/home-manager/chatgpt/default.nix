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
  toml = pkgs.formats.toml { };
  setups = lib.filterAttrs (_: setup: setup.enable) cfg.profiles;
  desktopSetups = lib.filterAttrs (_: setup: setup.desktop.enable) setups;
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
      ${setup.afterMerge}
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
        assertion = desktopSetups == { } || pkgs.stdenv.hostPlatform.isLinux;
        message = "Codex setup desktop launchers are only supported on Linux.";
      }
    ]
    ++ lib.mapAttrsToList (name: setup: {
      assertion =
        builtins.match "[a-zA-Z0-9][a-zA-Z0-9._-]*" name != null
        && lib.hasPrefix "/" setup.codexHome
        && (!setup.desktop.enable || lib.hasPrefix "/" setup.desktop.userDataDir);
      message = "Codex setup ${name} requires a safe name and absolute home/profile paths.";
    }) setups;

    home.packages =
      (valuesOf (s: s.finalPackage) setups) ++ (valuesOf (s: s.desktop.finalPackage) desktopSetups);
    home.activation = lib.mapAttrs' (
      name: setup:
      lib.nameValuePair "mergeCodexSetup-${name}" (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${mergeScript name setup}
          ${setup.activationScript}
        ''
      )
    ) setups;
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mapAttrs' (
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
      ) setups
    );
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mapAttrs' (
        name: setup:
        lib.nameValuePair "${setup.command}-config-merge" {
          enable = true;
          config = {
            ProgramArguments = [ "${mergeScript name setup}" ];
            ProcessType = "Background";
            RunAtLoad = true;
          };
        }
      ) setups
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
