{
  inputs,
  config,
  lib,
  pkgs,
  meta,
  ...
}:

let
  cfg = config.corncheese.development;

  onePassPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''
    else
      "~/.1password/agent.sock";
  homeJumpHosts = [
    "pve"
    "bigbrain"
  ];

  pkl-vscode = pkgs.vscode-utils.buildVscodeMarketplaceExtension rec {
    mktplcRef = {
      name = "pkl-vscode";
      version = "0.21.0";
      publisher = "apple";
    };
    vsix = builtins.fetchurl {
      url = "https://github.com/apple/pkl-vscode/releases/download/${mktplcRef.version}/pkl-vscode-${mktplcRef.version}.vsix";
      sha256 = "sha256:0jgbsxllqd1vhqzd83vv7bjg2hb951hqg6wflxxxalxvj4zlni79";
    };
  };

  clionHashes = import ./clion-hashes.nix;
  mkClion =
    { clionPkg, version }:
    if (version == clionPkg.version) then
      clionPkg
    else
      (
        if !(builtins.hasAttr version clionHashes) then
          throw "Invalid CLion version '${version}'. Available versions: ${lib.concatStringsSep ", " (builtins.attrNames clionHashes)}"
        else
          clionPkg.overrideAttrs rec {
            inherit version;
            src = pkgs.fetchurl {
              url = "https://download.jetbrains.com/cpp/CLion-${version}.tar.gz";
              hash = clionHashes.${version};
            };
          }
      );
  clionVersion = cfg.jetbrains.clion.versionOverride;

in
{
  imports = [ inputs.vscode-server.homeModules.default ];

  options = {
    corncheese.development = {
      ssh = {
        enable = lib.mkEnableOption "corncheese developer ssh config";
        onePassword = lib.mkEnableOption "corncheese developer ssh 1password integration";
      };
      vscode = {
        enable = lib.mkEnableOption "corncheese vscode config";
      };
      electronics = {
        enable = lib.mkEnableOption "corncheese electronics suite";
      };
      mechanical = {
        enable = lib.mkEnableOption "corncheese mechanical suite";
      };
      audio = {
        enable = lib.mkEnableOption "corncheese audio suite";
      };
      rust = {
        enable = lib.mkEnableOption "Rust development tools";
      };
      jetbrains = {
        enable = lib.mkEnableOption "corncheese jetbrains suite";
        clion = {
          versionOverride = lib.mkOption {
            type = with lib.types; nullOr str;
            description = "Override the version of CLion to install";
            default = pkgs.jetbrains.clion.version;
          };
        };
      };
      photo = {
        enable = lib.mkEnableOption "corncheese photo editing suite";
      };
    };
  };

  config = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };

    services.vscode-server.enable = true;

    programs.vscode = lib.mkIf cfg.vscode.enable {
      enable = true;
      package = pkgs.vscodium;
      profiles.default =
        let
          nix-vscode-extensions = inputs.nix-vscode-extensions.extensions.${meta.system};
        in
        {
          enableUpdateCheck = false;
          enableExtensionUpdateCheck = false;
          extensions =
            with pkgs;
            builtins.concatLists [
              [
                # Visual
                vscode-extensions.catppuccin.catppuccin-vsc
                vscode-extensions.catppuccin.catppuccin-vsc-icons

                # Git
                vscode-extensions.eamodio.gitlens

                # Remote
                vscode-extensions.ms-vscode-remote.remote-ssh
                vscode-extensions.ms-vscode-remote.remote-ssh-edit

                # C++
                vscode-extensions.ms-vscode.cpptools-extension-pack
                vscode-extensions.xaver.clang-format
                vscode-extensions.ms-vscode.cmake-tools

                # Nix
                vscode-extensions.jnoortheen.nix-ide
                vscode-extensions.signageos.signageos-vscode-sops

                # Python
                vscode-extensions.ms-python.python
                nix-vscode-extensions.open-vsx.detachhead.basedpyright
                vscode-extensions.ms-python.debugpy
                vscode-extensions.charliermarsh.ruff
                vscode-extensions.njpwerner.autodocstring

                # Misc
                nix-vscode-extensions.open-vsx.tamasfe.even-better-toml
                vscode-extensions.fill-labs.dependi

                # Pkl
                pkl-vscode
              ]
              (lib.optionals cfg.rust.enable [ vscode-extensions.rust-lang.rust-analyzer ])
              (lib.optionals (cfg.electronics.enable && cfg.rust.enable) [
                nix-vscode-extensions.open-vsx.probe-rs.probe-rs-debugger
              ])
            ];
          userSettings = {
            # General
            "extensions.autoUpdate" = false;
            "workbench.settings.editor" = "json";
            "explorer.confirmDelete" = false;
            "explorer.confirmDragAndDrop" = false;

            # Git
            "git.confirmSync" = false;
            "git.enableSmartCommit" = true;

            # Theming
            # "editor.fontFamily" = lib.mkForce "MesloLGM Nerd Font Mono";
            "editor.fontFamily" = lib.mkForce "Maple Mono NF CN";
            "terminal.integrated.fontFamily" = lib.mkForce "MesloLGM Nerd Font Mono";
            "workbench.colorTheme" = lib.mkForce "Catppuccin Mocha";
            "workbench.iconTheme" = "catppuccin-mocha";

            # C++
            "cmake.pinnedCommands" = [
              "workbench.action.tasks.configureTaskRunner"
              "workbench.action.tasks.runTask"
            ];

            # Remote
            "remote.SSH.useLocalServer" = false;

            # Pkl
            "pkl.cli.path" = "${inputs.pkl-flake.packages.${meta.system}.default}/bin/pkl";

            # Nix
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = lib.getExe pkgs.nixd;
            "nix.serverSettings" = {
              "nixd" = {
                "formatting" = {
                  "command" = [ (lib.getExe pkgs.nixfmt) ];
                };
                "nixpkgs" = {
                  "expr" = "import (builtins.getFlake \"/home/conroy/.config/system-config\").inputs.nixpkgs { }";
                };
                "options" = {
                  "nixos" = {
                    "expr" =
                      "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options";
                  };
                  "home-manager" = {
                    "expr" =
                      "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options.home-manager.users.type.getSubOptions []";
                  };
                };
              };
            };
            "[nix]" = {
              "editor.formatOnSave" = true;
            };

            # Python
            "[python]" = {
              "editor.formatOnSave" = true;
              "editor.defaultFormatter" = "charliermarsh.ruff";
            };
            "ruff.enable" = true;
            "ruff.format.backend" = "internal";
            "ruff.importStrategy" = "fromEnvironment";
            "ruff.logLevel" = "debug";
            "autoDocstring.docstringFormat" = "one-line-sphinx";

            # Misc languages
            "redhat.telemetry.enabled" = false;
            "[toml]" = {
              "editor.formatOnSave" = true;
              "editor.defaultFormatter" = "tamasfe.even-better-toml";
            };
          };
        };
    };

    home.file = lib.mkMerge [
      (lib.mkIf cfg.ssh.enable (
        let
          # Get all files from the source directory
          sshFiles = builtins.readDir ./pubkeys;

          # Create a set of file mappings for each identity file
          fileMapper = filename: {
            # Target path will be in ~/.ssh/
            ".ssh/${filename}".source = ./pubkeys + "/${filename}";
          };
        in
        lib.mkMerge [
          (lib.foldl (acc: filename: acc // (fileMapper filename)) { } (builtins.attrNames sshFiles))
        ]
      ))
    ];

    xdg.configFile = lib.mkIf cfg.ssh.onePassword {
      "1Password/ssh/agent.toml".text = ''
        [[ssh-keys]]
        vault = "Private"
        item = "conroy-home"

        [[ssh-keys]]
        vault = "Private"
        item = "GitHub"

        [[ssh-keys]]
        vault = "Private"
        item = "github-signing-key"

        [[ssh-keys]]
        vault = "Work"
      '';
    };

    home.packages =
      with pkgs;
      builtins.concatLists [
        [
          # Nix
          nixd
          nixfmt-rfc-style
          nix-output-monitor

          meld # Visual diff tool
          inputs.pkl-flake.packages.${meta.system}.default # pkl-cli
          pyright

          pkgs.nerd-fonts.meslo-lg
        ]
        (lib.optionals cfg.electronics.enable (
          [
            kicad
            stm32cubemx
          ]
          ++ (lib.optionals (builtins.hasAttr "waveforms" pkgs) [ pkgs.waveforms ])
          ++ (lib.optionals (builtins.hasAttr "j-link" pkgs) [ pkgs.j-link ])
          ++ (lib.optionals (builtins.hasAttr "xtc-tools" pkgs) [ pkgs.xtc-tools ])
        ))
        (lib.optionals (cfg.electronics.enable && cfg.rust.enable) [
          probe-rs-tools
        ])
        (lib.optionals cfg.rust.enable [
          rustc
          cargo
          clippy
          rustfmt
          rust-analyzer
        ])
        (lib.optionals cfg.mechanical.enable [
          prusa-slicer
          freecad-wayland
        ])
        (lib.optionals cfg.audio.enable [ ardour ])
        (lib.optionals cfg.jetbrains.enable ([
          (inputs.nix-jetbrains-plugins.lib."${meta.system}".buildIdeWithPlugins pkgs.jetbrains "pycharm" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "com.koxudaxi.ruff"
            "systems.fehn.intellijdirenv"
            "nix-idea"
          ])
          (pkgs.jetbrains.plugins.addPlugins
            (mkClion {
              clionPkg = pkgs.jetbrains.clion;
              version = clionVersion;
            })
            (
              with inputs.nix-jetbrains-plugins.plugins."${meta.system}";
              [
                clion."${clionVersion}"."com.intellij.plugins.vscodekeymap"
                clion."${clionVersion}"."com.github.catppuccin.jetbrains"
                clion."${clionVersion}"."nix-idea"
                clion."${clionVersion}"."systems.fehn.intellijdirenv"
              ]
            )
          )
          (inputs.nix-jetbrains-plugins.lib."${meta.system}".buildIdeWithPlugins pkgs.jetbrains "rust-rover" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "systems.fehn.intellijdirenv"
            "nix-idea"
          ])
        ]))
        (lib.optionals cfg.photo.enable [
          (inputs.affinity.packages.${meta.system}.v3)
        ])
      ];

    # programs.jetbrains-remote = {
    #   enable = true;
    #   ides = with pkgs.jetbrains; [
    #     pycharm-professional
    #   ];
    # };

    programs.git = {
      enable = true;
      settings = {
        merge.tool = "meld";
        mergetool.meld.cmd = ''meld "$LOCAL" "$BASE" "$REMOTE" --output "$MERGED"'';
        diff.algorithm = "patience";
      };
      # TODO: move this to scm module
      ignores =
        let
          gitignoreSrc = pkgs.fetchFromGitHub {
            owner = "github";
            repo = "gitignore";
            rev = "ceea7cab239eece5cb9fd9416e433a9497c2d747";
            hash = "sha256-YOPkqYJXinGHCbuCpHLS76iIWqUvYZh6SaJ0ROGoHc4=";
          };
          gitignoreText = builtins.concatStringsSep "\n" (
            builtins.concatLists [
              (lib.optionals cfg.jetbrains.enable [
                (builtins.readFile "${gitignoreSrc}/Global/JetBrains.gitignore")
              ])
              (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                (builtins.readFile "${gitignoreSrc}/Global/macOS.gitignore")
              ])
              (lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                (builtins.readFile "${gitignoreSrc}/Global/Linux.gitignore")
              ])
            ]
          );
        in
        lib.filter (value: !(lib.hasPrefix "#" value || value == "")) (lib.splitString "\n" gitignoreText);
    };

    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "beluga" = {
          hostname = "corncheese.org";
          user = "conroycheers";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "pve" = {
          hostname = "10.1.1.3";
          user = "root";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "bigbrain" = {
          hostname = "bigbrain.lan";
          user = "conroy";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        home = {
          host = (lib.concatStringsSep " " homeJumpHosts);
          proxyJump = "beluga";
        };
        "*" = {
          forwardAgent = false;
          addKeysToAgent = "no";
          compression = false;
          identityAgent = onePassPath;
          hashKnownHosts = true;
        };
      };
    };
  };
}
