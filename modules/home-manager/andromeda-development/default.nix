{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.andromeda.development;

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
      ANTHROPIC_DEFAULT_OPUS_MODEL = "global.anthropic.claude-opus-4-6-v1";
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
    mkdir -p "${config.home.homeDirectory}/.claude"

    if [ -f "${claudeSettingsFile}" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' \
        "${claudeSettingsFile}" \
        "${claudeSettingsSource}" \
        > "${claudeSettingsFile}.tmp" && mv "${claudeSettingsFile}.tmp" "${claudeSettingsFile}"
    else
      cp "${claudeSettingsSource}" "${claudeSettingsFile}"
    fi
  '';
in
{
  options = {
    andromeda.development = {
      enable = lib.mkEnableOption "andromeda development config";
      tftpServer.enable = lib.mkEnableOption "andromeda tftp dev server";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets."andromeda.aws-home-config.credentials" = {
      rekeyFile = lib.repoSecret "andromeda/aws-home-config/credentials.age";
    };

    home.sessionVariables = {
      ROS_DOMAIN_ID = "38";
      CARGO_NET_GIT_FETCH_WITH_CLI = "true";
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
      matchBlocks =
        (lib.concatMapAttrs (name: hostname: {
          "${name}".hostname = hostname;
          "${name}-root".hostname = hostname;
        }) abiAliases)
        // {
          abi-dev = {
            host = (lib.concatStringsSep " " (abiHosts ++ abiHostGlobs));
            user = abiUser;
          };
          abi-dev-abi = {
            match = "host ${lib.concatStringsSep "," (abiHosts ++ abiHostGlobs)} user ${abiUser}";
            extraOptions = {
              PubkeyAuthentication = "no";
            };
          };
          abi-dev-root = {
            match = "host ${lib.concatStringsSep "," abiHostGlobs} user root";
            identityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
          };
          abi-dev-root-alias = {
            host = (lib.concatStringsSep " " abiRootHosts);
            user = "root";
            identityFile = "${config.home.homeDirectory}/.ssh/abi_root.id_ed25519.pub";
          };

          "hydraq" = {
            hostname = "hq.dromeda.com.au";
            user = "nixremote";
            port = 8367;
            identityFile = "${config.home.homeDirectory}/.ssh/andromeda_build.id_ed25519.pub";
          };
          "hydra-master" = {
            hostname = "hydra.dromeda.com.au";
            user = "root";
            port = 22;
            identityFile = "${config.home.homeDirectory}/.ssh/andromeda_infra.id_ed25519.pub";
          };
          "*" = {
            forwardAgent = false;
            hashKnownHosts = true;
          };

          "kombu" = {
            hostname = "10.11.5.126";
            proxyJump = "root@babi-1-dev";
            identityFile = "${config.home.homeDirectory}/.ssh/conroy_work.id_ed25519.pub";
          };
        };
    };

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
      };
    };
  };
}
