{
  config,
  lib,
  pkgs,
  inputs,
  meta,
  ...
}:

let
  cfg = config.andromeda.development;
  codexAndromedaHome = "${config.home.homeDirectory}/.codex-andromeda";
  codexAndromedaConfigFile = "${codexAndromedaHome}/config.toml";
  codexPackage = inputs.codex-flake.packages.${meta.system}.codex;
  ccusagePackage = inputs.llm-agents.packages.${meta.system}.ccusage;
  andromedaShellHook =
    inputs.andromeda-shell-config.packages.${pkgs.stdenv.hostPlatform.system}.andromeda-shell-hook;
  codexAzureWorkaroundLastCheckedVersion = "0.147.0";
  # Codex 0.147.0 wraps Responses Lite tools in a `functions` namespace with an
  # empty description, which Azure rejects. Remove this override after
  # openai/codex#37380 is fixed in the packaged Codex release.
  codexAzureModelCatalog = pkgs.runCommand "codex-andromeda-azure-model-catalog.json" { } ''
    source=${codexPackage.src}/codex-rs/models-manager/models.json

    matched="$(${pkgs.jq}/bin/jq \
      '[.models[] | select(.slug | test("^gpt-5\\.6-(sol|terra|luna)$"))] | length' \
      "$source")"
    if [ "$matched" -ne 3 ]; then
      echo "expected three GPT-5.6 models in the bundled Codex catalog, found $matched" >&2
      exit 1
    fi

    ${pkgs.jq}/bin/jq \
      '(.models[] | select(.slug | test("^gpt-5\\.6-(sol|terra|luna)$")) | .use_responses_lite) = false' \
      "$source" > "$out"
  '';
  # A live GitHub fetch cannot be part of pure flake evaluation, so check on activation instead.
  checkCodexAzureWorkaround = pkgs.writeShellScript "check-codex-azure-workaround" ''
    issue="$(${pkgs.curl}/bin/curl \
      --fail \
      --location \
      --max-time 5 \
      --silent \
      https://api.github.com/repos/openai/codex/issues/37380 || true)"

    if [ "$(${pkgs.jq}/bin/jq -r '.state // empty' <<< "$issue")" = "closed" ]; then
      echo "warning: openai/codex#37380 is closed; re-check and remove the codex-andromeda Azure workaround" >&2
    fi
  '';

  slackMcpReadOnlyTools = [
    "channels_list"
    "channels_me"
    "conversations_history"
    "conversations_replies"
    "conversations_search_messages"
    "conversations_unreads"
    "users_search"
  ];
  codexAndromedaConfig = (pkgs.formats.toml { }).generate "codex-andromeda-config.toml" {
    model = "gpt-5.6-sol";
    model_catalog_json = "${codexAzureModelCatalog}";
    model_provider = "azure";
    model_reasoning_effort = "high";
    personality = "pragmatic";
    tui.pet = "stacky";

    features.multi_agent_v2.tool_namespace = "agents";

    mcp_servers.atlassian.url = "https://mcp.atlassian.com/v1/mcp/authv2";

    model_providers.azure = {
      name = "Azure OpenAI";
      base_url = "https://andromeda-developer-au.openai.azure.com/openai/v1";
      wire_api = "responses";

      auth = {
        command = "az";
        args = [
          "account"
          "get-access-token"
          "--resource"
          "https://cognitiveservices.azure.com"
          "--query"
          "accessToken"
          "-o"
          "tsv"
        ];
        timeout_ms = 60000;
        refresh_interval_ms = 1800000;
      };
    };

    mcp_servers.slack = {
      command = "${pkgs.codex-slack-mcp}/bin/codex-slack-mcp";
      args = [
        "--transport"
        "stdio"
        "--enabled-tools"
        (lib.concatStringsSep "," slackMcpReadOnlyTools)
      ];
      env_vars = [
        "SLACK_MCP_XOXP_TOKEN"
        "SLACK_MCP_XOXB_TOKEN"
      ];
      default_tools_approval_mode = "prompt";
      startup_timeout_sec = 10;
      tool_timeout_sec = 60;
    };
  };
  codexAndromedaRemovedNixKeys = [ ];
  codexAndromedaMergePython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.tomlkit
  ]);
  codexAndromedaMergeScript = pkgs.writeText "merge-codex-andromeda-config.py" ''
    import os
    import sys
    from pathlib import Path

    import tomlkit


    def merge_config(existing, desired):
        for key, desired_value in desired.items():
            if key in existing and mergeable(existing[key], desired_value):
                merge_config(existing[key], desired_value)
            else:
                existing[key] = desired_value


    def mergeable(existing_value, desired_value):
        return hasattr(existing_value, "items") and hasattr(desired_value, "items")


    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    target.parent.mkdir(parents=True, exist_ok=True)

    desired_config = tomlkit.parse(source.read_text())
    existing_config = tomlkit.document()
    if target.exists() or target.is_symlink():
        try:
            existing_config = tomlkit.parse(target.read_text())
        except FileNotFoundError:
            pass

    if target.is_symlink():
        target.unlink()

    merge_config(existing_config, desired_config)
    for removed_key in sys.argv[3:]:
        existing_config.pop(removed_key, None)

    tmp = target.with_name(f"{target.name}.tmp")
    tmp.write_text(tomlkit.dumps(existing_config))
    os.replace(tmp, target)
  '';
  mergeCodexAndromedaConfig = pkgs.writeShellScript "merge-codex-andromeda-config" ''
    ${codexAndromedaMergePython}/bin/python \
      ${codexAndromedaMergeScript} \
      ${codexAndromedaConfig} \
      "${codexAndromedaConfigFile}" \
      ${lib.escapeShellArgs codexAndromedaRemovedNixKeys}
  '';
  herdrPackage = inputs.llm-agents.packages.${meta.system}.herdr;
  installHerdrCodexAndromedaIntegration = pkgs.writeShellScript "install-herdr-codex-andromeda-integration" ''
    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export CODEX_HOME=${lib.escapeShellArg codexAndromedaHome}

    ${lib.getExe herdrPackage} integration install codex
  '';
  codex-andromeda-wrapped = pkgs.symlinkJoin {
    name = "codex-andromeda-wrapped";
    paths = [ codexPackage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      mv $out/bin/codex $out/bin/codex-andromeda
      wrapProgram $out/bin/codex-andromeda \
        --set CODEX_HOME "${codexAndromedaHome}" \
        --run '${pkgs.coreutils}/bin/mkdir -p "${codexAndromedaHome}"' \
        --prefix PATH : ${
          lib.makeBinPath [
            ccusagePackage
            pkgs.azure-cli
            pkgs.ripgrep
            pkgs.fd
            pkgs.gnused
            pkgs.gawk
            pkgs.jq
            pkgs.curl
            pkgs.wget2
            pkgs.gnutar
            pkgs.unzip
            pkgs.just
          ]
        }
    '';
  };

  abiUser = "abi";
  abiAliases = {
    "flabi" = "abi-andr-dev-1";
    "agx" = "10.11.120.231";
    "audiobox" = "10.11.4.99";
  };
  abiHostGlobs = [
    "abi-andr-*"
    "*abi-*-*"
  ];
  abiHosts = builtins.attrNames abiAliases;
  abiRootHosts = map (host: host + "-root") abiHosts;

  claudeSettings = {
    awsAuthRefresh = "aws sso login --sso-session Andromeda";
    env = {
      CLAUDE_CODE_USE_BEDROCK = "1";
      AWS_REGION = "us-west-2";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "global.anthropic.claude-sonnet-4-6";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "global.anthropic.claude-haiku-4-5-20251001-v1:0";
      ANTHROPIC_DEFAULT_OPUS_MODEL = "global.anthropic.claude-opus-4-8";
      AWS_PROFILE = "sandbox";
    };
    skipDangerousModePermissionPrompt = true;
    attribution = {
      commit = "";
      pr = "";
    };
  };
  claudeSettingsFile = "${config.home.homeDirectory}/.claude/settings.json";
  claudeSettingsSource = pkgs.writeText "claude-settings.json" (builtins.toJSON claudeSettings);
  mergeClaudeSettings = pkgs.writeShellScript "merge-claude-settings" ''
    ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/.claude"

    if [ -f "${claudeSettingsFile}" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
        "${claudeSettingsFile}" \
        "${claudeSettingsSource}" \
        > "${claudeSettingsFile}.tmp" && ${pkgs.coreutils}/bin/mv "${claudeSettingsFile}.tmp" "${claudeSettingsFile}"
    else
      ${pkgs.coreutils}/bin/cp "${claudeSettingsSource}" "${claudeSettingsFile}"
    fi
  '';
in
{
  options = {
    andromeda.development = {
      enable = lib.mkEnableOption "andromeda development config";
      codexPackage = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        internal = true;
        default = codex-andromeda-wrapped;
        description = "The wrapped Codex CLI package owned by the Andromeda profile";
      };
      tftpServer.enable = lib.mkEnableOption "andromeda tftp dev server";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (lib.versionOlder codexAzureWorkaroundLastCheckedVersion codexPackage.version) ''
      codex-andromeda uses the Azure Responses Lite workaround for openai/codex#37380,
      but Codex ${codexPackage.version} is newer than the last checked version
      ${codexAzureWorkaroundLastCheckedVersion}. Re-check whether the workaround is still needed.
    '';

    age.secrets."andromeda.aws-home-config.credentials" = {
      rekeyFile = lib.repoSecret "andromeda/aws-home-config/credentials.age";
    };

    home.sessionVariables = {
      ROS_DOMAIN_ID = "38";
      CARGO_NET_GIT_FETCH_WITH_CLI = "true";
      ABI_SSH_KEY = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519";
    };

    home.file = lib.mkMerge [
      (
        let
          # Get all files from the source directory
          sshFiles = builtins.readDir ./pubkeys;

          # Create a set of file mappings for each identity file
          fileMapper = filename: {
            # Target path will be in ~/.ssh/
            ".ssh/${filename}".source = pkgs.copyPathToStore (./pubkeys + "/${filename}");
          };
        in
        lib.foldl (acc: filename: acc // (fileMapper filename)) { } (builtins.attrNames sshFiles)
        // {
          "${config.home.homeDirectory}/.aws/credentials".source =
            config.lib.file.mkOutOfStoreSymlink
              config.age.secrets."andromeda.aws-home-config.credentials".path;
        }
      )
      {
        ".config/nix-vm/vm.nix" = {
          text = ''
            {
              nixpkgs.hostPlatform = "${pkgs.stdenv.hostPlatform.system}";
              virtualisation.vmVariant = {
                virtualisation = {
                  host.pkgs = import <nixpkgs> { };
                  cores = 4;
                  memorySize = 8192;
                  resolution = { x = 1280; y = 720; };
                };
              };
            }
          '';
        };
      }
    ];

    xdg.configFile = {
      "1Password/ssh/agent.toml".text = lib.mkBefore ''
        [[ssh-keys]]
        vault = "Work"
      '';
    };

    home.activation.mergeCodexAndromedaConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${mergeCodexAndromedaConfig}
    '';

    home.activation.installHerdrCodexAndromedaIntegration =
      lib.hm.dag.entryAfter [ "mergeCodexAndromedaConfig" ]
        ''
          ${installHerdrCodexAndromedaIntegration}
        '';

    home.activation.checkCodexAzureWorkaround =
      lib.hm.dag.entryAfter
        [
          "mergeCodexAndromedaConfig"
        ]
        ''
          ${checkCodexAzureWorkaround}
        '';

    systemd.user.services.codex-andromeda-config-merge = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "Merge Codex Andromeda config with Nix-defined configuration";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${mergeCodexAndromedaConfig}";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    systemd.user.services.claude-settings-merge = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "Merge Claude settings with Nix-defined configuration";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${mergeClaudeSettings}";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    launchd.agents.codex-andromeda-config-merge = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${mergeCodexAndromedaConfig}" ];
        ProcessType = "Background";
        RunAtLoad = true;
      };
    };

    launchd.agents.claude-settings-merge = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${mergeClaudeSettings}" ];
        ProcessType = "Background";
        RunAtLoad = true;
      };
    };

    programs.ssh = {
      enable = true;
      settings =
        (lib.concatMapAttrs (name: hostname: {
          "${name}".HostName = hostname;
          "${name}-root".HostName = hostname;
        }) abiAliases)
        // {
          abi-dev = {
            header = "Host ${lib.concatStringsSep " " (abiHosts ++ abiHostGlobs)}";
            User = abiUser;
          };
          abi-dev-abi = {
            header = "Match host ${lib.concatStringsSep "," (abiHosts ++ abiHostGlobs)} user ${abiUser}";
            PubkeyAuthentication = "no";
          };
          abi-dev-root = {
            header = "Match host ${lib.concatStringsSep "," abiHostGlobs} user root";
            IdentityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
          };
          abi-dev-root-alias = {
            header = "Host ${lib.concatStringsSep " " abiRootHosts}";
            User = "root";
            IdentityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
          };

          "hydraq" = {
            HostName = "hq.dromeda.com.au";
            User = "nixremote";
            Port = 8367;
            IdentityFile = "${config.home.homeDirectory}/.ssh/andromeda_build.id_ed25519.pub";
          };
          "hydra-master" = {
            HostName = "hydra.dromeda.com.au";
            User = "root";
            Port = 22;
            IdentityFile = "${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub";
          };
          "acacia banksia" = {
            header = "Host acacia banksia";
            User = "root";
            IdentitiesOnly = true;
            IdentityFile = "${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub";
            ControlMaster = "auto";
            ControlPath = "${config.home.homeDirectory}/.cache/ssh-control/%C";
            ControlPersist = "4h";
          };
          "stage-a-acacia" = {
            HostName = "acacia.tail738663.ts.net";
            User = "root";
            IdentitiesOnly = true;
            IdentityFile = "${config.home.homeDirectory}/.ssh/stage_a_nix_builder_ed25519";
            ControlMaster = "auto";
            ControlPath = "${config.home.homeDirectory}/.cache/ssh-control/%C";
            ControlPersist = "4h";
          };
          "stage-a-banksia" = {
            HostName = "banksia.tail738663.ts.net";
            User = "root";
            IdentitiesOnly = true;
            IdentityFile = "${config.home.homeDirectory}/.ssh/stage_a_nix_builder_ed25519";
            ControlMaster = "auto";
            ControlPath = "${config.home.homeDirectory}/.cache/ssh-control/%C";
            ControlPersist = "4h";
          };
          "*" = {
            ForwardAgent = false;
            HashKnownHosts = true;
          };
        };
    };

    home.packages = [
      andromedaShellHook
      codex-andromeda-wrapped
      pkgs.atlassian-cli
    ];

    # The dispatcher must run after direnv or direnv-instant has selected the
    # checkout-provided driver.
    programs.bash.initExtra = lib.mkAfter ''
      eval "$(${andromedaShellHook}/bin/andromeda-shell-hook hook bash)"
    '';

    programs.zsh.initContent = lib.mkAfter ''
      eval "$(${andromedaShellHook}/bin/andromeda-shell-hook hook zsh)"
    '';

    programs.fish.interactiveShellInit = lib.mkAfter ''
      ${andromedaShellHook}/bin/andromeda-shell-hook hook fish | source
    '';

    programs.awscli = {
      enable = true;
      settings = {
        "default" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile sandbox" = {
          sso_session = "Andromeda";
          sso_account_id = "440744238060";
          sso_role_name = "AWSPowerUserAccess";
        };

        "sso-session Andromeda" = {
          sso_start_url = "https://d-9767b8dd82.awsapps.com/start/#/?tab=accounts";
          sso_region = "ap-southeast-2";
          sso_registration_scopes = "sso:account:access";
        };

        "profile iot-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile memories-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile logs-archive-crossaccount" = {
          region = "ap-southeast-2";
          output = "json";
        };

        "profile abi-deploy" = {
          sso_session = "Andromeda";
          sso_account_id = "210362323009";
          sso_role_name = "AbiDeployPermSet";
          region = "ap-southeast-2";
          output = "json";
        };

        "profile iot-creds-au-dev" = {
          sso_session = "Andromeda";
          sso_account_id = "235494781452";
          sso_role_name = "IoTCredsBucketPermSet-au-dev";
          region = "ap-southeast-2";
          output = "json";
        };

        "profile iot-creds-us-dev" = {
          sso_session = "Andromeda";
          sso_account_id = "235494781452";
          sso_role_name = "IoTCredsBucketPermSet-us-dev";
          region = "us-west-2";
          output = "json";
        };

        "profile iot-creds-au-prod" = {
          sso_session = "Andromeda";
          sso_account_id = "263383612339";
          sso_role_name = "IoTCredsBucketPermSet-au-prod";
          region = "ap-southeast-2";
          output = "json";
        };

        "profile iot-creds-us-prod" = {
          sso_session = "Andromeda";
          sso_account_id = "263383612339";
          sso_role_name = "IoTCredsBucketPermSet-us-prod";
          region = "us-west-2";
          output = "json";
        };
      };
    };
  };
}
