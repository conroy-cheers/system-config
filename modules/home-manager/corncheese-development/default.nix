{ inputs, config, lib, pkgs, meta, ... }:

let
  cfg = config.corncheese.development;

  onePassPath = "~/.1password/agent.sock";
  homeJumpHosts = [ "pve" "bigbrain" ];

  pkl-vscode = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "pkl-vscode";
      version = "0.18.2";
      publisher = "apple";
    };
    vsix = builtins.fetchurl {
      url = "https://github.com/apple/pkl-vscode/releases/download/0.18.2/pkl-vscode-0.18.2.vsix";
      sha256 = "sha256:0lvsf1y9ib05n6idbl0171ncdjb0r01kibp6128k2j8ncxyvpvy3";
      name = "pkl-vscode-0.18.2.zip";
    };
  };

  clionHashes = import ./clion-hashes.nix;
  mkClion = { clionPkg, version }:
    if (version == clionPkg.version) then clionPkg else
    (if ! (builtins.hasAttr version clionHashes) then
      throw "Invalid CLion version '${version}'. Available versions: ${lib.concatStringsSep ", " (builtins.attrNames clionHashes)}"
    else
      clionPkg.overrideAttrs rec {
        inherit version;
        src = pkgs.fetchurl {
          url = "https://download.jetbrains.com/cpp/CLion-${version}.tar.gz";
          hash = clionHashes.${version};
        };
      });
  clionVersion = cfg.jetbrains.clion.versionOverride;

in
{
  imports = [
    inputs.vscode-server.homeModules.default
  ];

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
      jetbrains = {
        enable = lib.mkEnableOption "corncheese jetbrains suite";
        clion = {
          versionOverride = lib.mkOption
            {
              type = with lib.types; nullOr str;
              description = "Override the version of CLion to install";
              default = pkgs.jetbrains.clion.version;
            };
        };
      };
    };
  };

  config = {
    services.vscode-server.enable = true;

    programs.vscode = lib.mkIf cfg.vscode.enable {
      enable = true;
      package = pkgs.vscodium;
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
      extensions = with pkgs; [
        vscode-extensions.continue.continue
        vscode-extensions.ms-vscode.cpptools-extension-pack
        vscode-extensions.xaver.clang-format
        vscode-extensions.ms-vscode.cmake-tools
        vscode-extensions.eamodio.gitlens
        vscode-extensions.jnoortheen.nix-ide
        vscode-extensions.ms-python.python
        vscode-extensions.ms-python.vscode-pylance
        vscode-extensions.ms-python.debugpy
        vscode-extensions.charliermarsh.ruff
        vscode-extensions.ms-vscode-remote.remote-ssh
        vscode-extensions.ms-vscode-remote.remote-ssh-edit
        vscode-extensions.rust-lang.rust-analyzer
        pkl-vscode
      ];
      userSettings = {
        "git.confirmSync" = false;
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "terminal.integrated.fontFamily" = lib.mkForce "FiraCode Nerd Font";
        "cmake.pinnedCommands" = [
          "workbench.action.tasks.configureTaskRunner"
          "workbench.action.tasks.runTask"
        ];
        "remote.SSH.useLocalServer" = false;
      };
    };

    home.file = lib.mkIf cfg.ssh.enable (
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
    );

    xdg.configFile = lib.mkIf cfg.ssh.onePassword {
      "1Password/ssh/agent.toml".text = ''
        [[ssh-keys]]
        vault = "Private"
        item = "conroy-home"

        [[ssh-keys]]
        vault = "Private"
        item = "GitHub"

        [[ssh-keys]]
        vault = "Work"
      '';
    };

    home.packages = with pkgs; builtins.concatLists [
      [
        meld # Visual diff tool
        jdk23
        inputs.pkl-flake.packages.${meta.system}.default # pkl-cli
      ]
      (lib.optionals cfg.electronics.enable [
        kicad
      ])
      (lib.optionals cfg.mechanical.enable [
        orca-slicer
        freecad-wayland
      ])
      (lib.optionals cfg.jetbrains.enable ([
        (inputs.nix-jetbrains-plugins.lib."${meta.system}".buildIdeWithPlugins pkgs.jetbrains "pycharm-professional" [
          "com.intellij.plugins.vscodekeymap"
          "com.github.catppuccin.jetbrains"
          "com.koxudaxi.ruff"
          "nix-idea"
        ])
        (pkgs.jetbrains.plugins.addPlugins
          (mkClion {
            clionPkg = pkgs.jetbrains.clion;
            version = clionVersion;
          })
          (with inputs.nix-jetbrains-plugins.plugins."${meta.system}"; [
            clion."${clionVersion}"."com.intellij.plugins.vscodekeymap"
            clion."${clionVersion}"."com.github.catppuccin.jetbrains"
            clion."${clionVersion}"."nix-idea"
          ]))
      ]))
    ];

    # programs.jetbrains-remote = {
    #   enable = true;
    #   ides = with pkgs.jetbrains; [
    #     pycharm-professional
    #   ];
    # };

    programs.git = {
      enable = true;
      extraConfig = {
        merge.tool = "meld";
        mergetool.meld.cmd = "meld \"$LOCAL\" \"$BASE\" \"$REMOTE\" --output \"$MERGED\"";
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
          gitignoreText = builtins.concatStringsSep "\n" [
            (builtins.readFile "${gitignoreSrc}/Global/JetBrains.gitignore")
          ];
        in
        lib.filter (value: !(lib.hasPrefix "#" value || value == "")) (lib.splitString "\n" gitignoreText);
    };

    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      forwardAgent = false;
      hashKnownHosts = true;

      # 1Password SSH agent config
      extraConfig = ''
        Host *
            IdentityAgent ${onePassPath}
      '';

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
      };
    };
  };
}
