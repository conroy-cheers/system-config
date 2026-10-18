{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  # The terminal is part of the desktop session, not the development suite.
  config = lib.mkIf (config.corncheese.desktop.enable || config.corncheese.wm.enable) {
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
          background-blur = config.corncheese.theming.themeDetails.terminalBackgroundBlur or 0;
          background-opacity =
            config.corncheese.theming.themeDetails.terminalOpacity
              or config.corncheese.theming.themeDetails.opacity;
          background-opacity-cells = config.corncheese.theming.themeDetails.terminalTuiTransparent or false;
        };
        installBatSyntax = isAvailable;
      };

  };
}
