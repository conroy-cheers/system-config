{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.desktop;
  inherit (lib) mkEnableOption mkIf;
in
{
  imports = [ ];

  options = {
    corncheese.desktop = {
      enable = mkEnableOption "corncheese desktop environment setup";
      mail.enable = mkEnableOption "conroy's mail configuration";
      firefox.enable = mkEnableOption "firefox configuration";
      chromium.enable = mkEnableOption "chromium configuration";
      element.enable = mkEnableOption "element configuration";
      media.enable = mkEnableOption "media viewer configuration";
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable {
      xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        defaultApplications = {
          "text/plain" = [ "neovide.desktop" ];
        };
      };
      xdg.terminal-exec = {
        enable = true;
        package = pkgs.xdg-terminal-exec-mkhl;
        settings = {
          Hyprland = [
            "com.mitchellh.ghostty.desktop"
          ];
          default = [
            "com.mitchellh.ghostty.desktop"
          ];
        };
      };

      programs.ghostty = {
        enable = true;
        # On macOS, the ghostty package is not available through Nix
        package = if pkgs.ghostty.meta.available then pkgs.ghostty else null;
        # enableZshIntegration = true;  # TODO flag or remove
        enableFishIntegration = true;
        settings = {
          keybind = [
          ];
          background-blur = 20;
        };
        installBatSyntax = pkgs.ghostty.meta.available;
      };

      home.packages = with pkgs; [
        slack
      ];

      programs.obsidian = {
        enable = true;
      };

      programs.neovide = {
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

      programs.mpv = {
        enable = true;
      };
    })
    (lib.mkIf cfg.media.enable {
      home.packages = with pkgs; [
        # plex-desktop
      ];

      services.plex-mpv-shim = {
        enable = true;
      };
    })
    (lib.mkIf cfg.mail.enable {
      age.secrets."corncheese.mail.icloud" = {
        rekeyFile = lib.repoSecret "corncheese/mail/icloud.age";
      };
      age.secrets."corncheese.mail.gmail" = {
        rekeyFile = lib.repoSecret "corncheese/mail/gmail.age";
      };
      age.secrets."corncheese.mail.andromeda" = {
        rekeyFile = lib.repoSecret "andromeda/mail/gmail.age";
      };

      accounts.email = {
        accounts.andromeda = {
          address = "conroy@dromeda.com.au";
          userName = "conroy@dromeda.com.au";
          flavor = "gmail.com";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.andromeda".path}";
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          aerc = {
            enable = true;
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
        accounts.gmail = {
          address = "cheers.conroy@gmail.com";
          userName = "cheers.conroy@gmail.com";
          flavor = "gmail.com";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.gmail".path}";
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          aerc = {
            enable = true;
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
        accounts.icloud = {
          address = "conroy.cheers@icloud.com";
          primary = true;
          aliases = [
            "conroy@corncheese.org"
            "conroy@conroycheers.me"
          ];
          userName = "conroy.cheers";
          passwordCommand = "cat ${config.age.secrets."corncheese.mail.icloud".path}";
          imap = {
            host = "imap.mail.me.com";
            port = 993;
          };
          smtp = {
            host = "smtp.mail.me.com";
            port = 587;
            tls.useStartTls = true;
          };
          realName = "Conroy Cheers";
          mbsync = {
            enable = true;
            create = "maildir";
          };
          notmuch.enable = true;
          thunderbird = {
            enable = true;
          };
        };
      };

      programs.mbsync = {
        enable = true;
      };
      programs.notmuch = {
        enable = true;
        hooks = {
          preNew = "mbsync --all";
        };
      };
      programs.thunderbird = {
        enable = true;
        profiles = {
          default = {
            isDefault = true;
          };
        };
      };
    })
  ];

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
