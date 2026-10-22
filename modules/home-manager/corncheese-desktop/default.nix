{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./minecraft-client.nix
    ./terminal.nix
  ];

  options.corncheese.desktop = {
    enable = lib.mkEnableOption "corncheese desktop environment setup";
    mail.enable = lib.mkEnableOption "conroy's mail configuration";
    firefox.enable = lib.mkEnableOption "firefox configuration";
    chromium.enable = lib.mkEnableOption "chromium configuration";
    element.enable = lib.mkEnableOption "element configuration";
    media.enable = lib.mkEnableOption "media viewer configuration";
    media.plezy.package = lib.mkPackageOption pkgs "plezy" { };
  };

  config = lib.mkMerge [
    (lib.mkIf config.corncheese.desktop.enable {
      xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        defaultApplications = {
          "text/plain" = [ "neovide.desktop" ];
        };
      };

      home.packages = with pkgs; [
        slack
      ];

      programs.obsidian = {
        enable = true;
      };

      programs.neovide = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        package = pkgs.neovide.overrideAttrs (old: {
          # Neovim 0.13 adds optional fields to API parameter metadata.
          # Backport the upstream parser fix until the next Neovide release.
          patches = (old.patches or [ ]) ++ [
            (pkgs.fetchurl {
              url = "https://github.com/neovide/neovide/commit/7af518d72c33907b57d3a6c54c67969857a13871.patch";
              hash = "sha256-cW/6J/Cv8SAZxUszMdSbI94YYYa18cGxScGBS0vGQfw=";
            })
          ];
        });
        settings = {
          fork = false;
          frame = "full";
          idle = true;
          maximized = false;
          mouse-cursor-icon = "arrow";
          neovim-bin = "${lib.getExe (
            if config.programs.nvf.enable then config.programs.nvf.finalPackage else pkgs.neovim
          )}";
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

      programs.firefox = lib.mkIf config.corncheese.desktop.firefox.enable {
        enable = true;
        configPath = ".mozilla/firefox";
        profiles.default = {
          id = 0;
          isDefault = true;
          extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
            onepassword-password-manager
            ublock-origin
          ];
        };
      };

      stylix.targets.firefox.profileNames = lib.mkIf config.corncheese.desktop.firefox.enable [
        "default"
      ];

      programs.chromium = lib.mkIf config.corncheese.desktop.chromium.enable {
        enable = true;
        package = pkgs.chromium;
        extensions = [
          { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; } # 1Password
          { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # uBlock Origin
        ];
      };

      programs.element-desktop = lib.mkIf config.corncheese.desktop.element.enable {
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
        enable = pkgs.stdenv.hostPlatform.isLinux;
      };
    })
    (lib.mkIf config.corncheese.desktop.media.enable {
      home.packages = [
        config.corncheese.desktop.media.plezy.package
      ];

      xdg.configFile."plex-mpv-shim/mpv.conf" = {
        force = true;
        text = ''
          vo=gpu-next
          gpu-api=vulkan
          gpu-context=waylandvk
          dither-depth=10

          target-colorspace-hint=no
          tone-mapping=bt.2390
          hdr-reference-white=203
          target-peak=400
          gamut-mapping-mode=perceptual
        '';
      };

      xdg.dataFile."plex/mpv.conf" = {
        force = true;
        text = ''
          ao=pulse
          audio-channels=stereo

          vo=gpu-next
          dither-depth=10

          target-colorspace-hint=no
          tone-mapping=bt.2390
          target-peak=400
          gamut-mapping-mode=perceptual
        '';
      };

      services.plex-mpv-shim = {
        enable = pkgs.stdenv.hostPlatform.isLinux;
      };
    })
    (lib.mkIf config.corncheese.desktop.mail.enable {
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

  meta = { };
}
