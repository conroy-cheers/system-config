{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  desktopCfg = config.corncheese.desktop;
  gamesCfg = config.corncheese.games;
  inherit (lib) mkEnableOption mkIf;
  filterOutLibrary = libraryName: libraries:
    builtins.filter (library: (library.name or "") != libraryName) libraries;
  filterOutLibraryPrefix = prefix: libraries:
    builtins.filter (library: !(lib.hasPrefix prefix (library.name or ""))) libraries;
  exportEnvVars = variables:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: values: ''export ${name}="${lib.concatStringsSep ":" (lib.toList values)}"'') variables
    );

  radianceJar = pkgs.fetchurl {
    url = "https://github.com/Minecraft-Radiance/Radiance/releases/download/v0.1.4-alpha/Radiance-0.1.4-alpha-fabric-1.21.4-linux.jar";
    hash = "sha256-Pj0h6u9/JkStheMobbAdvOPIL9ITgEMA4wQPZ9hHB3E=";
  };

  fabricApiJar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/sVqpGIb1/fabric-api-0.119.3%2B1.21.4.jar";
    hash = "sha256-ay3wDFI5TDmA+HE3/Wk37o10iItFyuZ9RwfMoCZ6bR8=";
  };

  irisJar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/YL57xq9U/versions/fDpuVzVr/iris-fabric-1.10.7%2Bmc1.21.11.jar";
    hash = "sha256-WMVdoYGJyRpJ+EfTzuRRYzojtXX7acDFtl3bJ0Q2yxk=";
  };

  sodiumJar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/AANobbMI/versions/UddlN6L4/sodium-fabric-0.8.7%2Bmc1.21.11.jar";
    hash = "sha256-wI+uhrNQqqio835zR5Kd848BzCNIzzHDImFVZL3FOYM=";
  };

  photonShaderZip = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/lLqFfGNs/versions/rz2vlXVm/photon_v1.2a.zip";
    hash = "sha256-pxNKEBOPbl/lI9r6I70ma6LlNiGsZaXiMpT+mhJbnXM=";
  };

  spbrResourcePackName = "SPBR-14.2.zip";
  spbrSource = pkgs.fetchFromGitHub {
    owner = "ShulkerSakura";
    repo = "SPBR";
    rev = "14.2";
    hash = "sha256-O3m5DpssE6fkv4NYI556jUf1LwUSxiEzUZ+WDL/EG1k=";
  };
  spbrResourcePackZip = pkgs.runCommandLocal spbrResourcePackName { nativeBuildInputs = [ pkgs.zip ]; } ''
    mkdir -p work
    cp -r ${spbrSource}/src/. work/
    chmod -R u+w work
    cd work
    zip -qr "$out" .
  '';

  photonOptionsTxt = pkgs.writeText "minecraft-photon-options.txt" ''
    guiScale:3
  '';

  corncraftServerName = "corncraft";
  corncraftServerAddress = "lasagne.xyz";
in
{
  imports = [ inputs.nixcraft.homeModules.default ];

  options = {
    corncheese.desktop = {
      enable = mkEnableOption "corncheese desktop environment setup";
      mail.enable = mkEnableOption "conroy's mail configuration";
      firefox.enable = mkEnableOption "firefox configuration";
      chromium.enable = mkEnableOption "chromium configuration";
      element.enable = mkEnableOption "element configuration";
      media.enable = mkEnableOption "media viewer configuration";
    };

    corncheese.games = {
      minecraft = mkEnableOption "Minecraft 1.21.4 client with Radiance";
    };
  };

  config = lib.mkMerge [
    {
      nixcraft = {
        client.instances = lib.mkDefault { };
        server.instances = lib.mkDefault { };
      };

      assertions = [
        {
          assertion = (!gamesCfg.minecraft) || pkgs.stdenv.hostPlatform.isLinux;
          message = "corncheese.games.minecraft requires a Linux Home Manager configuration.";
        }
      ];
    }
    (mkIf desktopCfg.enable {
      xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        defaultApplications = {
          "text/plain" = [ "neovide.desktop" ];
        };
      };
      xdg.terminal-exec = {
        enable = true;
        package = pkgs.xdg-terminal-exec;
        settings = {
          Hyprland = [
            "com.mitchellh.ghostty.desktop"
          ];
          default = [
            "com.mitchellh.ghostty.desktop"
          ];
        };
      };

      programs.ghostty =
        let
          # On macOS, the ghostty package is not available through Nix
          isAvailable = inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system} ? "default";
        in
        {
          enable = true;
          package =
            if isAvailable then inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.default else null;
          # enableZshIntegration = true;  # TODO flag or remove
          enableFishIntegration = true;
          settings = {
            keybind = [
            ];
            background-blur = 20;
          };
          installBatSyntax = isAvailable;
        };

      home.packages = with pkgs; [
        slack
      ];

      programs.obsidian = {
        enable = true;
      };

      programs.neovide = {
        enable = true;
        settings = {
          fork = false;
          frame = "full";
          idle = true;
          maximized = false;
          mouse-cursor-icon = "arrow";
          neovim-bin = "${lib.getExe (
            if config.programs.nvf.enable then config.programs.nvf.finalPackage else pkgs.neovim
          )}";
          no-multigrid = false;
          srgb = true;
          tabs = true;
          theme = "auto";
          title-hidden = false;
          vsync = true;
          wsl = false;

          font = {
            normal = [ "MesloLGM Nerd Font Mono" ];
            # size = 12.0;
          };
        };
      };

      programs.firefox = mkIf desktopCfg.firefox.enable {
        enable = true;
        profiles.default = {
          id = 0;
          isDefault = true;
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            onepassword-password-manager
            ublock-origin
          ];
        };
      };

      stylix.targets.firefox.profileNames = mkIf desktopCfg.firefox.enable [ "default" ];

      programs.chromium = mkIf desktopCfg.chromium.enable {
        enable = true;
        package = pkgs.chromium;
        extensions = [
          { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; } # 1Password
          { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # uBlock Origin
        ];
      };

      programs.element-desktop = mkIf desktopCfg.element.enable {
        enable = true;
        package = pkgs.element-desktop;
        settings = {
          default_server_config = {
            "m.homeserver" = {
              base_url = "https://matrix.corncheese.org";
              server_name = "corncheese.org";
            };
            "m.identity_server" = {
              base_url = "https://vector.im";
            };
          };
          disable_custom_urls = false;
          disable_guests = false;
          disable_login_language_selector = true;
          disable_3pid_login = false;
          force_verification = false;
          brand = "Element";
          integrations_ui_url = "https://scalar.vector.im/";
          integrations_rest_url = "https://scalar.vector.im/api";
        };
      };

      programs.mpv = {
        enable = pkgs.stdenv.hostPlatform.isLinux;
      };
    })
    (lib.mkIf desktopCfg.media.enable {
      home.packages = with pkgs; [
        # plex-desktop
      ];

      services.plex-mpv-shim = {
        enable = pkgs.stdenv.hostPlatform.isLinux;
      };
    })
    (lib.mkIf desktopCfg.mail.enable {
      age.secrets."corncheese.mail.icloud" = {
        rekeyFile = lib.repoSecret "corncheese/mail/icloud.age";
      };
      age.secrets."corncheese.mail.gmail" = {
        rekeyFile = lib.repoSecret "corncheese/mail/gmail.age";
      };
      age.secrets."corncheese.mail.andromeda" = {
        rekeyFile = lib.repoSecret "andromeda/mail/gmail.age";
      };

      accounts.email = {
        accounts.andromeda = {
          address = "conroy@dromeda.com.au";
          userName = "conroy@dromeda.com.au";
          flavor = "gmail.com";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.andromeda".path}";
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          aerc = {
            enable = true;
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
        accounts.gmail = {
          address = "cheers.conroy@gmail.com";
          userName = "cheers.conroy@gmail.com";
          flavor = "gmail.com";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.gmail".path}";
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          aerc = {
            enable = true;
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
        accounts.icloud = {
          address = "conroy.cheers@icloud.com";
          primary = true;
          aliases = [
            "conroy@corncheese.org"
            "conroy@conroycheers.me"
          ];
          userName = "conroy.cheers";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.icloud".path}";
          imap = {
            host = "imap.mail.me.com";
            port = 993;
          };
          smtp = {
            host = "smtp.mail.me.com";
            port = 587;
            tls.useStartTls = true;
          };
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
      };

      programs.mbsync = {
        enable = true;
      };
      programs.notmuch = {
        enable = true;
        hooks = {
          preNew = "mbsync --all";
        };
      };
      programs.thunderbird = {
        enable = true;
        profiles = {
          default = {
            isDefault = true;
          };
        };
      };
    })
    (mkIf (gamesCfg.minecraft && pkgs.stdenv.hostPlatform.isLinux) (
      let
        minecraftAuthTool = pkgs.callPackage ../../../pkgs/minecraft-auth { };
        minecraftInstanceSyncTool = pkgs.callPackage ../../../pkgs/minecraft-instance-sync { };

        syncMinecraftInstance = instance: ''
          ${lib.getExe minecraftInstanceSyncTool} \
            --instance-dir ${lib.escapeShellArg instance.absoluteDir} \
            --server-name ${lib.escapeShellArg corncraftServerName} \
            --server-address ${lib.escapeShellArg corncraftServerAddress} \
            --resource-pack ${lib.escapeShellArg spbrResourcePackName}
        '';

        minecraftPhotonOnlineLauncher = makeMinecraftOnlineLauncher {
          launcherName = "minecraft-photon-online";
          instance = config.nixcraft.client.instances.photonOnline;
        };

        minecraftRadianceOnlineLauncher = makeMinecraftOnlineLauncher {
          launcherName = "minecraft-radiance-online";
          instance = config.nixcraft.client.instances.radianceOnline;
        };

        makeDesktopEntry =
          {
            fileName,
            name,
            comment,
            exec,
            terminal ? false,
            icon ? null,
            categories ? [ "Game" ],
            mimeType ? null,
          }:
          pkgs.writeText fileName ''
            [Desktop Entry]
            Type=Application
            Version=1.5
            Name=${name}
            Comment=${comment}
            Exec=${exec}
            Terminal=${if terminal then "true" else "false"}
            ${lib.optionalString (icon != null) "Icon=${icon}"}
            Categories=${lib.concatStringsSep ";" categories};
            ${lib.optionalString (mimeType != null) "MimeType=${mimeType}"}
          '';

        makeMinecraftOnlineLauncher =
          {
            launcherName,
            instance,
          }:
          pkgs.writeShellScriptBin launcherName ''
            set -euo pipefail

            auth_account="''${MINECRAFT_AUTH_ACCOUNT:-default}"
            auth_json="$(${lib.getExe minecraftAuthTool} ensure --account "$auth_account" --json)"
            username="$(${pkgs.jq}/bin/jq -r '.username' <<<"$auth_json")"
            uuid="$(${pkgs.jq}/bin/jq -r '.uuid' <<<"$auth_json")"
            access_token="$(${pkgs.jq}/bin/jq -r '.access_token' <<<"$auth_json")"

            ${exportEnvVars instance.envVars}
            ${instance.finalPreLaunchShellScript}

            cd ${lib.escapeShellArg instance.absoluteDir}

            exec "${instance.java.package}/bin/java" \
              ${instance.java.finalArgumentShellString} \
              ${instance.finalArgumentShellString} \
              --username "$username" \
              --uuid "$uuid" \
              --accessToken "$access_token" \
              "$@"
          '';
      in
      {
        nixcraft = {
          enable = true;
          server.instances = { };
          client = {
            shared = {
              useDiscreteGPU = false;
            };

            instances.radiance = {
              enable = true;
              version = "1.21.4";
              placeFilesAtActivation = true;
              account = {
                username = config.home.username;
                offline = true;
              };
              libraries = lib.mkForce (filterOutLibrary "org.ow2.asm:asm:9.6" config.nixcraft.client.instances.radiance.meta.versionData.libraries);
              runtimeLibs = with pkgs; [
                zlib
                bzip2
                xz
                openssl
              ];

              fabricLoader = {
                enable = true;
                version = "0.18.3";
              };

              binEntry = {
                enable = true;
                name = "minecraft-radiance";
              };

              desktopEntry.enable = false;

              files = {
                "mods/fabric-api-0.119.3+1.21.4.jar".source = fabricApiJar;
                "mods/Radiance-0.1.4-alpha-fabric-1.21.4-linux.jar".source = radianceJar;
                "resourcepacks/${spbrResourcePackName}".source = spbrResourcePackZip;
              };

              activationShellScript = lib.mkAfter (syncMinecraftInstance config.nixcraft.client.instances.radiance);
            };

            instances.radianceOnline = {
              enable = true;
              version = "1.21.4";
              placeFilesAtActivation = true;
              account = lib.mkForce null;
              libraries = lib.mkForce (filterOutLibrary "org.ow2.asm:asm:9.6" config.nixcraft.client.instances.radianceOnline.meta.versionData.libraries);
              runtimeLibs = with pkgs; [
                zlib
                bzip2
                xz
                openssl
              ];

              fabricLoader = {
                enable = true;
                version = "0.18.3";
              };

              binEntry.enable = false;
              desktopEntry.enable = false;

              files = {
                "mods/fabric-api-0.119.3+1.21.4.jar".source = fabricApiJar;
                "mods/Radiance-0.1.4-alpha-fabric-1.21.4-linux.jar".source = radianceJar;
                "resourcepacks/${spbrResourcePackName}".source = spbrResourcePackZip;
              };

              activationShellScript = lib.mkAfter (syncMinecraftInstance config.nixcraft.client.instances.radianceOnline);
            };

            instances.photon = {
              enable = true;
              version = "1.21.11";
              placeFilesAtActivation = true;
              account = {
                username = config.home.username;
                offline = true;
              };
              libraries = lib.mkForce (filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photon.meta.versionData.libraries);

              fabricLoader = {
                enable = true;
                version = "0.18.5";
              };

              binEntry = {
                enable = true;
                name = "minecraft-photon";
              };

              desktopEntry.enable = false;

              files = {
                "mods/iris-fabric-1.10.7+mc1.21.11.jar".source = irisJar;
                "mods/sodium-fabric-0.8.7+mc1.21.11.jar".source = sodiumJar;
                "shaderpacks/photon_v1.2a.zip".source = photonShaderZip;
                "resourcepacks/${spbrResourcePackName}".source = spbrResourcePackZip;
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue {}).generate "iris.properties" {
                    enableShaders = true;
                    shaderPack = "photon_v1.2a.zip";
                  };
                  method = lib.mkForce "copy-init";
                };
                "options.txt" = {
                  source = photonOptionsTxt;
                  method = lib.mkForce "copy-init";
                };
              };

              activationShellScript = lib.mkAfter (syncMinecraftInstance config.nixcraft.client.instances.photon);
            };

            instances.photonOnline = {
              enable = true;
              version = "1.21.11";
              placeFilesAtActivation = true;
              account = lib.mkForce null;
              libraries = lib.mkForce (filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photonOnline.meta.versionData.libraries);

              fabricLoader = {
                enable = true;
                version = "0.18.5";
              };

              binEntry.enable = false;
              desktopEntry.enable = false;

              files = {
                "mods/iris-fabric-1.10.7+mc1.21.11.jar".source = irisJar;
                "mods/sodium-fabric-0.8.7+mc1.21.11.jar".source = sodiumJar;
                "shaderpacks/photon_v1.2a.zip".source = photonShaderZip;
                "resourcepacks/${spbrResourcePackName}".source = spbrResourcePackZip;
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue {}).generate "iris.properties" {
                    enableShaders = true;
                    shaderPack = "photon_v1.2a.zip";
                  };
                  method = lib.mkForce "copy-init";
                };
                "options.txt" = {
                  source = photonOptionsTxt;
                  method = lib.mkForce "copy-init";
                };
              };

              activationShellScript = lib.mkAfter (syncMinecraftInstance config.nixcraft.client.instances.photonOnline);
            };
          };
        };

        home.file = {
          ".local/share/applications/minecraft-photon-online.desktop".source = makeDesktopEntry {
            fileName = "minecraft-photon-online.desktop";
            name = "Minecraft 1.21.11 (with Photon)";
            comment = "Online Fabric client with Iris, Sodium, Photon, and Microsoft sign-in";
            exec = lib.getExe minecraftPhotonOnlineLauncher;
            terminal = true;
            categories = [ "Game" ];
          };

          ".local/share/applications/minecraft-radiance-online.desktop".source = makeDesktopEntry {
            fileName = "minecraft-radiance-online.desktop";
            name = "Minecraft 1.21.4 (with Radiance)";
            comment = "Online Fabric client with Radiance and Microsoft sign-in";
            exec = lib.getExe minecraftRadianceOnlineLauncher;
            terminal = true;
            categories = [ "Game" ];
          };
        };

        home.packages = [
          minecraftAuthTool
          minecraftPhotonOnlineLauncher
          minecraftRadianceOnlineLauncher
        ];
      }
    ))
  ];

  meta = {
  };
}
