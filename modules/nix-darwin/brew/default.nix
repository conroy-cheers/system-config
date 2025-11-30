{
  inputs,
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
    nix-homebrew = {
      # Install Homebrew under the default prefix
      enable = true;

      # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
      enableRosetta = true;

      # User owning the Homebrew prefix
      user = config.system.primaryUser;

      # Optional: Declarative tap management
      taps = {
        "homebrew/homebrew-core" = inputs.homebrew-core;
        "homebrew/homebrew-cask" = inputs.homebrew-cask;
      };
      # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
      mutableTaps = false;
    };

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
        "ghostty"
        "slack"
      ];
      extraConfig = ''
        cask_args appdir: "~/Applications"
      '';
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
