{config, lib, pkgs, ...}:
{
  programs.vscode = {
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
}
