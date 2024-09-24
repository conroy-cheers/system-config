{config, lib, ...}:
{
  programs.vscode = {
    enable = true;
    userSettings = {
      "terminal.integrated.fontFamily" = lib.mkForce "FiraCode Nerd Font";
    };
  };
}
