{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
  cfg = config.corncheese.brew;
in
{
  imports = [ ];

  options = {
    corncheese.brew = {
      enable = mkEnableOption "corncheese brew config";
    };
  };

  config = mkIf cfg.enable {
    # Requires Homebrew to be installed
    system.activationScripts.corncheeseUserActivation.text = ''
      sudo -u ${config.system.primaryUser} bash -c '
        if ! xcode-select --version 2>/dev/null; then
          $DRY_RUN_CMD xcode-select --install
        fi
        if ! ${config.homebrew.brewPrefix}/brew --version 2>/dev/null; then
          $DRY_RUN_CMD /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi 
      '
    '';

    home-manager.users.${config.system.primaryUser}.programs.zsh.initContent = ''
      eval "$(${config.homebrew.brewPrefix}/brew shellenv)"
    '';

    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = false; # Don't update during rebuild
        upgrade = true;
        cleanup = "zap"; # Uninstall all programs not declared
      };
      global = {
        brewfile = true; # Run brew bundle from anywhere
        lockfiles = false; # Don't save lockfile (since running from anywhere)
      };
      taps = [
      ];
      brews = [
        "libusb"
        "openssl"
      ];
      casks = [
        "slack"
      ];
      extraConfig = ''
        cask_args appdir: "~/Applications"
      '';
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ corncheese ];
  };
}
