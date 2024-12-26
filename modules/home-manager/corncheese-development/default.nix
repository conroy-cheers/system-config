{ config, lib, pkgs, ... }:

let
  cfg = config.corncheese.development;

  pkl-vscode = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "pkl-vscode";
      version = "0.18.1";
      publisher = "apple";
    };
    vsix = builtins.fetchurl {
      url = "https://github.com/apple/pkl-vscode/releases/download/0.18.1/pkl-vscode-0.18.1.vsix";
      sha256 = "sha256:1vsizpwvlrm3qacrciyq7kdzklk9a4xqvakb890fny909sp2b86n";
      name = "pkl-vscode-0.18.1.zip";
    };
  };
in
{
  options = {
    corncheese.development = {
      vscode = {
        enable = lib.mkEnableOption "corncheese vscode config";
      };
    };
  };

  config = {
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
  };
}
