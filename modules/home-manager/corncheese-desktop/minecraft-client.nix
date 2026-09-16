{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  normalizeMinecraftLibraries =
    inputs.nixcraft.lib.maven.mkNormalizedMinecraftLibraryAttrs pkgs.stdenv.hostPlatform
      (
        { url, sha1, ... }:
        pkgs.fetchurl { inherit url sha1; }
      );
  filterOutLibrary =
    libraryName: libraries:
    lib.filterAttrs (name: _: name != libraryName) (normalizeMinecraftLibraries libraries);
  filterOutLibraryPrefix =
    prefix: libraries:
    lib.filterAttrs (name: _: !(lib.hasPrefix prefix name)) (normalizeMinecraftLibraries libraries);

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

  iris26Jar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/YL57xq9U/versions/Yi5E3d2l/iris-fabric-1.10.8%2Bmc26.1.jar";
    hash = "sha256-Aa85HHybu7gGDnmKWeocEt5oGFnQx4l/rcYdkVblyiw=";
  };

  sodiumJar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/AANobbMI/versions/UddlN6L4/sodium-fabric-0.8.7%2Bmc1.21.11.jar";
    hash = "sha256-wI+uhrNQqqio835zR5Kd848BzCNIzzHDImFVZL3FOYM=";
  };

  sodium26Jar = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/AANobbMI/versions/Amr4VcZo/sodium-fabric-0.8.7%2Bmc26.1.jar";
    hash = "sha256-+QaQEkF0cpvFUGgoJWnMmde5y1Q2hiaci6IpXVL5bh0=";
  };

  photonShaderZip = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/lLqFfGNs/versions/rz2vlXVm/photon_v1.2a.zip";
    hash = "sha256-pxNKEBOPbl/lI9r6I70ma6LlNiGsZaXiMpT+mhJbnXM=";
  };

  spbrResourcePackZip = pkgs.runCommandLocal "SPBR-14.2.zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
    mkdir -p work
    cp -r ${
      pkgs.fetchFromGitHub {
        owner = "ShulkerSakura";
        repo = "SPBR";
        rev = "14.2";
        hash = "sha256-O3m5DpssE6fkv4NYI556jUf1LwUSxiEzUZ+WDL/EG1k=";
      }
    }/src/. work/
    chmod -R u+w work
    cd work
    zip -qr "$out" .
  '';

  photonOptionsTxt = pkgs.writeText "minecraft-photon-options.txt" ''
    guiScale:3
  '';

  minecraftRuntimeLibs = with pkgs; [
    (lib.getLib stdenv.cc.cc)
    glfw3-minecraft
    openal
    alsa-lib
    libjack2
    libpulseaudio
    pipewire
    libGL
    libx11
    libxcursor
    libxext
    libxrandr
    libxxf86vm
    udev
    vulkan-loader
    flite
    libxtst
    libxkbcommon
    libxt
  ];

  minecraftRuntimePrograms = with pkgs; [
    busybox
    xrandr
  ];

in
{
  imports = [ inputs.nixcraft.homeModules.default ];

  options.corncheese.games = {
    minecraft = lib.mkEnableOption "Minecraft 1.21.4 client with Radiance";
  };

  config = lib.mkMerge [
    {
      nixcraft = {
        client.instances = lib.mkDefault { };
        server.instances = lib.mkDefault { };
      };

      assertions = [
        {
          assertion = (!config.corncheese.games.minecraft) || pkgs.stdenv.hostPlatform.isLinux;
          message = "corncheese.games.minecraft requires a Linux Home Manager configuration.";
        }
      ];
    }
    (lib.mkIf (config.corncheese.games.minecraft && pkgs.stdenv.hostPlatform.isLinux) (
      let
        minecraftAuthTool = pkgs.callPackage ../../../pkgs/minecraft-auth { };

        syncMinecraftInstance = instance: ''
          ${lib.getExe (pkgs.callPackage ../../../pkgs/minecraft-instance-sync { })} \
            --instance-dir ${lib.escapeShellArg instance.absoluteDir} \
            --server-name ${lib.escapeShellArg "corncraft"} \
            --server-address ${lib.escapeShellArg "lasagne.xyz"} \
            --resource-pack ${lib.escapeShellArg "SPBR-14.2.zip"}
        '';

        minecraftPhotonOnlineLauncher = makeMinecraftOnlineLauncher {
          launcherName = "minecraft-photon-online";
          instance = config.nixcraft.client.instances.photonOnline;
        };

        minecraftPhoton26OnlineLauncher = makeMinecraftOnlineLauncher {
          launcherName = "minecraft-photon-26-online";
          instance = config.nixcraft.client.instances.photon26Online;
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

            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: values: ''export ${name}="${lib.concatStringsSep ":" (lib.toList values)}"''
              ) instance.envVars
            )}
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
              libraries = lib.mkForce (
                filterOutLibrary "org.ow2.asm:asm:9.6" config.nixcraft.client.instances.radiance.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce (
                minecraftRuntimeLibs
                ++ (with pkgs; [
                  zlib
                  bzip2
                  xz
                  openssl
                ])
              );
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

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
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
              };

              activationShellScript = lib.mkAfter (
                syncMinecraftInstance config.nixcraft.client.instances.radiance
              );
            };

            instances.radianceOnline = {
              enable = true;
              version = "1.21.4";
              placeFilesAtActivation = true;
              account = lib.mkForce null;
              libraries = lib.mkForce (
                filterOutLibrary "org.ow2.asm:asm:9.6" config.nixcraft.client.instances.radianceOnline.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce (
                minecraftRuntimeLibs
                ++ (with pkgs; [
                  zlib
                  bzip2
                  xz
                  openssl
                ])
              );
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

              fabricLoader = {
                enable = true;
                version = "0.18.3";
              };

              binEntry.enable = false;
              desktopEntry.enable = false;

              files = {
                "mods/fabric-api-0.119.3+1.21.4.jar".source = fabricApiJar;
                "mods/Radiance-0.1.4-alpha-fabric-1.21.4-linux.jar".source = radianceJar;
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
              };

              activationShellScript = lib.mkAfter (
                syncMinecraftInstance config.nixcraft.client.instances.radianceOnline
              );
            };

            instances.photon = {
              enable = true;
              version = "1.21.11";
              placeFilesAtActivation = true;
              account = {
                username = config.home.username;
                offline = true;
              };
              libraries = lib.mkForce (
                filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photon.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce minecraftRuntimeLibs;
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

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
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue { }).generate "iris.properties" {
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
              libraries = lib.mkForce (
                filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photonOnline.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce minecraftRuntimeLibs;
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

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
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue { }).generate "iris.properties" {
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

              activationShellScript = lib.mkAfter (
                syncMinecraftInstance config.nixcraft.client.instances.photonOnline
              );
            };

            instances.photon26 = {
              enable = true;
              version = "26.1";
              placeFilesAtActivation = true;
              account = {
                username = config.home.username;
                offline = true;
              };
              libraries = lib.mkForce (
                filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photon26.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce minecraftRuntimeLibs;
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

              fabricLoader = {
                enable = true;
                version = "0.18.5";
              };

              binEntry = {
                enable = true;
                name = "minecraft-photon-26";
              };

              desktopEntry.enable = false;

              files = {
                "mods/iris-fabric-1.10.8+mc26.1.jar".source = iris26Jar;
                "mods/sodium-fabric-0.8.7+mc26.1.jar".source = sodium26Jar;
                "shaderpacks/photon_v1.2a.zip".source = photonShaderZip;
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue { }).generate "iris.properties" {
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

              activationShellScript = lib.mkAfter (
                syncMinecraftInstance config.nixcraft.client.instances.photon26
              );
            };

            instances.photon26Online = {
              enable = true;
              version = "26.1";
              placeFilesAtActivation = true;
              account = lib.mkForce null;
              libraries = lib.mkForce (
                filterOutLibraryPrefix "org.ow2.asm:asm:" config.nixcraft.client.instances.photon26Online.meta.versionData.libraries
              );
              runtimeLibs = lib.mkForce minecraftRuntimeLibs;
              runtimePrograms = lib.mkForce minecraftRuntimePrograms;

              fabricLoader = {
                enable = true;
                version = "0.18.5";
              };

              binEntry.enable = false;
              desktopEntry.enable = false;

              files = {
                "mods/iris-fabric-1.10.8+mc26.1.jar".source = iris26Jar;
                "mods/sodium-fabric-0.8.7+mc26.1.jar".source = sodium26Jar;
                "shaderpacks/photon_v1.2a.zip".source = photonShaderZip;
                "resourcepacks/SPBR-14.2.zip" = {
                  source = spbrResourcePackZip;
                  method = lib.mkForce "copy";
                };
                "config/iris.properties" = {
                  source = (pkgs.formats.keyValue { }).generate "iris.properties" {
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

              activationShellScript = lib.mkAfter (
                syncMinecraftInstance config.nixcraft.client.instances.photon26Online
              );
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

          ".local/share/applications/minecraft-photon-26-online.desktop".source = makeDesktopEntry {
            fileName = "minecraft-photon-26-online.desktop";
            name = "Minecraft 26.1 (with Photon)";
            comment = "Online Fabric client with Iris, Sodium, Photon, and Microsoft sign-in";
            exec = lib.getExe minecraftPhoton26OnlineLauncher;
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
          minecraftPhoton26OnlineLauncher
          minecraftRadianceOnlineLauncher
        ];
      }
    ))
  ];
}
