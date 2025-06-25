{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.desktop;
  inherit (lib) mkEnableOption mkOption mkIf;
in
{
  imports = [ ];

  options = {
    corncheese.desktop = {
      enable = mkEnableOption "corncheese desktop environment setup";
      neovide.enable = mkEnableOption "neovide configuration";
      thunderbird.enable = mkEnableOption "thunderbird configuration";
      firefox.enable = mkEnableOption "firefox configuration";
      chromium.enable = mkEnableOption "chromium configuration";
      element.enable = mkEnableOption "element configuration";
    };
  };

  config = mkIf cfg.enable {
    xdg.mimeApps = lib.mkIf pkgs.hostPlatform.isLinux {
      enable = true;
      defaultApplications = {
        "text/plain" = [ "neovide.desktop" ];
      };
    };

    programs.neovide = mkIf cfg.neovide.enable {
      enable = true;
      settings = {
        fork = false;
        frame = "full";
        idle = true;
        maximized = false;
        mouse-cursor-icon = "arrow";
        neovim-bin = "${pkgs.neovim}/bin/nvim";
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

    programs.thunderbird = mkIf cfg.thunderbird.enable {
      enable = true;
      profiles = {
        default = {
          isDefault = true;
        };
      };
    };

    programs.firefox = mkIf cfg.firefox.enable {
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

    programs.chromium = mkIf cfg.chromium.enable {
      enable = true;
      package = pkgs.chromium;
      extensions = [
        { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; } # 1Password
        { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # uBlock Origin
      ];
    };

    programs.element-desktop = mkIf cfg.element.enable {
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
  };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
