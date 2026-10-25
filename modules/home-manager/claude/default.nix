{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.programs.claude;
  homeDirectory = config.home.homeDirectory;
  configXdgHome = config.xdg.configHome;
  upstreamConfigDir = "${homeDirectory}/.claude";
  json = pkgs.formats.json { };
  profiles = lib.filterAttrs (_: profile: profile.enable) cfg.profiles;
  desktops = lib.filterAttrs (_: profile: profile.desktop.enable) profiles;
  commonPackages = with pkgs; [
    gh
    jq
    yq
    curl
    python3
    openssl
    ripgrep
    fd
    dig
    tree
    file
    xxd
    bc
    sqlite
    envsubst
    gnutar
    gzip
    unzip
    zstd
    shellcheck
    findutils
    diffutils
    patch
    nix-diff
    lsof
    gnused
    gawk
    nmap
    tcpdump
    socat
    netcat
    wget2
  ];
  isBedrock = profile: (profile.settings.env.CLAUDE_CODE_USE_BEDROCK or "") == "1";
  toolPath =
    profile:
    lib.makeBinPath (
      commonPackages ++ profile.extraPackages ++ lib.optional (isBedrock profile) pkgs.awscli2
    );
  configDirArgs =
    profile:
    if profile.configDir == upstreamConfigDir then
      [
        "--unset"
        "CLAUDE_CONFIG_DIR"
      ]
    else
      [
        "--set"
        "CLAUDE_CONFIG_DIR"
        profile.configDir
      ];
  profileEnvironment =
    profile:
    if profile.configDir == upstreamConfigDir then
      "unset CLAUDE_CONFIG_DIR"
    else
      "export CLAUDE_CONFIG_DIR=${lib.escapeShellArg profile.configDir}";
  inferenceDefaults =
    profile:
    let
      env = profile.settings.env or { };
      models =
        lib.concatMap
          (
            tier:
            lib.optional (env ? ${"ANTHROPIC_DEFAULT_${lib.toUpper tier}_MODEL"}) {
              name = env.${"ANTHROPIC_DEFAULT_${lib.toUpper tier}_MODEL"};
              anthropicFamilyTier = tier;
            }
          )
          [
            "sonnet"
            "opus"
            "haiku"
          ];
    in
    lib.optionalAttrs (isBedrock profile) (
      {
        inferenceProvider = "bedrock";
        inferenceBedrockProfile = env.AWS_PROFILE or "default";
        inferenceBedrockAwsCliPath = lib.getExe pkgs.awscli2;
      }
      // lib.optionalAttrs (env ? AWS_REGION || env ? AWS_DEFAULT_REGION) {
        inferenceBedrockRegion = env.AWS_REGION or env.AWS_DEFAULT_REGION;
      }
      // lib.optionalAttrs (models != [ ]) {
        inferenceModels = models;
      }
    );
  inferenceId =
    name:
    let
      hash = builtins.hashString "sha256" "home-manager-claude-${name}";
    in
    "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-4${builtins.substring 12 3 hash}-a${builtins.substring 15 3 hash}-${builtins.substring 18 12 hash}";
  mergeFile = source: target: extraArgs: ''
    ${pkgs.python3}/bin/python3 ${./merge-settings.py} ${source} \
      ${lib.escapeShellArg target} ${lib.escapeShellArgs extraArgs}
  '';
  mergeScript =
    name: profile:
    pkgs.writeShellScript "merge-${profile.command}-settings" ''
      set -e
      ${mergeFile (json.generate "claude-${name}-settings.json" profile.settings)
        "${profile.configDir}/settings.json"
        [
          "--obsolete"
          (json.generate "claude-${name}-obsolete.json" profile.obsoleteSettings)
        ]
      }
      ${lib.optionalString profile.desktop.enable ''
        ${mergeFile (json.generate "claude-${name}-desktop.json" profile.desktop.settings)
          "${profile.desktop.userDataDir}/claude_desktop_config.json"
          [ ]
        }
        ${lib.optionalString (profile.desktop.inferenceSettings != { }) ''
          ${mergeFile (json.generate "claude-${name}-inference.json" profile.desktop.inferenceSettings)
            "${profile.desktop.userDataDir}/configLibrary/${inferenceId name}.json"
            [ ]
          }
          ${mergeFile
            (json.generate "claude-${name}-inference-meta.json" {
              appliedId = inferenceId name;
              entries = [
                {
                  id = inferenceId name;
                  name = profile.desktop.name;
                }
              ];
            })
            "${profile.desktop.userDataDir}/configLibrary/_meta.json"
            [
              "--profile-entry"
              (inferenceId name)
            ]
          }
        ''}
      ''}
      ${profile.afterMerge}
    '';
  cliPackage =
    profile:
    pkgs.symlinkJoin {
      name = "${profile.command}-wrapped";
      paths = [ profile.package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        ${lib.optionalString (profile.command != "claude") ''
          mv "$out/bin/claude" "$out/bin/${profile.command}"
        ''}
        wrapProgram "$out/bin/${profile.command}" \
          --argv0 claude \
          ${lib.escapeShellArgs (configDirArgs profile)} \
          --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg profile.configDir}"} \
          --run ${lib.escapeShellArg profile.beforeLaunch} \
          --add-flags ${lib.escapeShellArg (lib.escapeShellArgs profile.extraArgs)} \
          --prefix PATH : ${lib.escapeShellArg (toolPath profile)}
      '';
      meta.mainProgram = profile.command;
    };
  desktopPackage =
    profile:
    pkgs.runCommand profile.desktop.command
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = profile.desktop.command;
      }
      ''
        mkdir -p "$out/bin" "$out/share/icons"
        ln -s ${profile.desktop.package}/share/icons/hicolor "$out/share/icons/hicolor"
        makeWrapper ${lib.getExe' profile.desktop.package "claude-desktop"} \
          "$out/bin/${profile.desktop.command}" \
          ${lib.escapeShellArgs (configDirArgs profile)} \
          --set CHROME_DESKTOP ${lib.escapeShellArg "${profile.desktop.desktopId}.desktop"} \
          --set BAMF_DESKTOP_FILE_HINT ${lib.escapeShellArg "${config.xdg.dataHome}/applications/${profile.desktop.desktopId}.desktop"} \
          --add-flags ${
            lib.escapeShellArg (
              lib.escapeShellArgs (
                [
                  "--user-data-dir=${profile.desktop.userDataDir}"
                ]
                ++ profile.desktop.extraArgs
              )
            )
          } \
          --prefix PATH : ${lib.escapeShellArg (toolPath profile)} \
          --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p ${
            lib.escapeShellArgs [
              profile.configDir
              profile.desktop.userDataDir
            ]
          }"}
      '';
  valuesOf = f: attrs: map f (builtins.attrValues attrs);
  unique = values: builtins.length values == builtins.length (lib.unique values);
in
{
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude CLI and desktop profiles";
    profiles = mkOption {
      default = { };
      description = ''
        Named Claude Code profiles with optional desktop launchers. Enabling
        the module creates a default profile for the regular claude command.
        User settings remain mutable and are merged at activation and login.
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
                default = if name == "default" then "claude" else "claude-${name}";
              };
              configDir = mkOption {
                type = types.str;
                default = "${homeDirectory}/.${config.command}";
                description = "Absolute Claude configuration directory. The standard ~/.claude path retains the upstream login and ~/.claude.json location.";
              };
              package = mkOption {
                type = types.package;
                default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
                description = "Unwrapped package providing bin/claude.";
              };
              finalPackage = mkOption {
                type = types.package;
                readOnly = true;
                default = cliPackage config;
                description = "Generated CLI wrapper.";
              };
              settings = mkOption {
                type = json.type;
                default = { };
              };
              obsoleteSettings = mkOption {
                type = json.type;
                default = { };
                description = "Obsolete managed values to remove only if the existing leaf still matches, before applying settings.";
              };
              extraPackages = mkOption {
                type = types.listOf types.package;
                default = [ ];
              };
              extraArgs = mkOption {
                type = types.listOf types.str;
                default = [ ];
              };
              beforeLaunch = mkOption {
                type = types.lines;
                default = "";
              };
              afterMerge = mkOption {
                type = types.lines;
                default = "";
              };
              activationScript = mkOption {
                type = types.lines;
                default = "";
                description = "Shell commands run after merging, with HOME and CLAUDE_CONFIG_DIR set for this profile.";
              };
              desktop = {
                enable = lib.mkEnableOption "a Claude desktop launcher for this profile";
                package = mkOption {
                  type = types.package;
                  default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
                };
                command = mkOption {
                  type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9._-]*";
                  default = "claude-desktop${lib.optionalString (name != "default") "-${name}"}";
                };
                desktopId = mkOption {
                  type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9._-]*";
                  default = "com.anthropic.Claude${lib.optionalString (name != "default") ".${name}"}";
                  description = "Desktop file ID for this launcher. Stock Claude windows retain the upstream com.anthropic.Claude window class.";
                };
                name = mkOption {
                  type = types.str;
                  default = "Claude${lib.optionalString (name != "default") " (${name})"}";
                };
                userDataDir = mkOption {
                  type = types.str;
                  default = "${configXdgHome}/Claude${lib.optionalString (name != "default") "-${name}"}${
                    lib.optionalString (config.desktop.inferenceSettings != { }) "-3p"
                  }";
                  description = "Separate Electron profile. Third-party profiles must end in -3p, matching the app's config-library location.";
                };
                settings = mkOption {
                  type = json.type;
                  default = { };
                  description = "Mutable claude_desktop_config.json settings, including desktop MCP servers.";
                };
                inferenceSettings = mkOption {
                  type = json.type;
                  default = inferenceDefaults config;
                  description = "Desktop third-party inference configuration. Bedrock region, AWS profile, and models default to the CLI settings.env values.";
                };
                extraArgs = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };
                finalPackage = mkOption {
                  type = types.package;
                  readOnly = true;
                  default = desktopPackage config;
                  description = "Generated desktop launcher.";
                };
              };
            };
          }
        )
      );
    };
  };
  config = lib.mkIf cfg.enable {
    programs.claude.profiles.default = lib.mkDefault { };
    assertions = [
      {
        assertion = unique (valuesOf (p: p.configDir) profiles);
        message = "Claude profiles must use distinct configDir directories.";
      }
      {
        assertion = unique (
          (valuesOf (p: p.command) profiles) ++ (valuesOf (p: p.desktop.command) desktops)
        );
        message = "Claude CLI and desktop commands must be unique.";
      }
      {
        assertion = unique (valuesOf (p: p.desktop.desktopId) desktops);
        message = "Claude desktop launcher IDs must be unique.";
      }
      {
        assertion = unique (valuesOf (p: p.desktop.userDataDir) desktops);
        message = "Claude desktop user data directories must be unique.";
      }
      {
        assertion = desktops == { } || pkgs.stdenv.hostPlatform.isLinux;
        message = "Claude profile desktop launchers are only supported on Linux.";
      }
    ]
    ++ lib.mapAttrsToList (name: profile: {
      assertion =
        builtins.match "[a-zA-Z0-9][a-zA-Z0-9._-]*" name != null
        && lib.hasPrefix "/" profile.configDir
        && (
          !profile.desktop.enable
          || (
            lib.hasPrefix "/" profile.desktop.userDataDir
            && (profile.desktop.inferenceSettings == { } || lib.hasSuffix "-3p" profile.desktop.userDataDir)
          )
        );
      message = "Claude profile ${name} requires a safe name, absolute paths, and a desktop path ending in -3p for third-party inference.";
    }) profiles;
    home.packages =
      (valuesOf (p: p.finalPackage) profiles) ++ (valuesOf (p: p.desktop.finalPackage) desktops);
    home.activation = lib.mapAttrs' (
      name: profile:
      lib.nameValuePair "mergeClaudeProfile-${name}" (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${mergeScript name profile}
          (
            export HOME=${lib.escapeShellArg homeDirectory}
            ${profileEnvironment profile}
            ${profile.activationScript}
          )
        ''
      )
    ) profiles;
    systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
      lib.mapAttrs' (
        name: profile:
        lib.nameValuePair "${profile.command}-settings-merge" {
          Unit = {
            Description = "Merge ${name} Claude settings";
            After = [ "default.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${mergeScript name profile}";
            RemainAfterExit = true;
          };
          Install.WantedBy = [ "default.target" ];
        }
      ) profiles
    );
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mapAttrs' (
        name: profile:
        lib.nameValuePair "${profile.command}-settings-merge" {
          enable = true;
          config = {
            ProgramArguments = [ "${mergeScript name profile}" ];
            ProcessType = "Background";
            RunAtLoad = true;
          };
        }
      ) profiles
    );
    xdg.desktopEntries = lib.mapAttrs' (
      _: profile:
      lib.nameValuePair profile.desktop.desktopId {
        name = profile.desktop.name;
        genericName = "AI assistant";
        exec = "${lib.getExe profile.desktop.finalPackage} %U";
        icon = "claude-desktop";
        terminal = false;
        categories = [
          "Development"
          "Utility"
        ];
        mimeType = lib.optional (profile.command == "claude") "x-scheme-handler/claude";
        settings.StartupWMClass = "com.anthropic.Claude";
      }
    ) desktops;
  };
}
