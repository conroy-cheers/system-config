{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.corncheese.wm;
  themeDetails = config.corncheese.theming.themeDetails;
  lua = lib.generators.mkLuaInline;

  waitForPipewire = pkgs.writeShellScriptBin "wait-for-pipewire" ''
    set -euo pipefail

    while ! ${pkgs.systemd}/bin/systemctl --user --quiet is-active pipewire.service \
       || ! ${pkgs.systemd}/bin/systemctl --user --quiet is-active wireplumber.service
    do
      sleep 0.1
    done
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      inputs.swww.packages.${pkgs.stdenv.hostPlatform.system}.swww
      cliphist
    ];

    wayland.windowManager.hyprland.settings = lib.mkMerge [
      {
        monitor = lib.mkDefault [
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
        ];

        on = {
          _args = [
            "hyprland.start"
            (lua ''
              function()
                hl.exec_cmd(${builtins.toJSON (lib.getExe waitForPipewire)})
                hl.exec_cmd("wl-paste --type text --watch cliphist store")
                hl.exec_cmd("wl-paste --type image --watch cliphist store")
                hl.exec_cmd("ghostty", { workspace = "1", silent = true })
                hl.exec_cmd("ghostty --title=btop -e btop", { workspace = "2", silent = true })
                hl.exec_cmd("ghostty --title=cava -e cava", { workspace = "2", silent = true })
                hl.exec_cmd(${builtins.toJSON (lib.getExe pkgs.plexamp)}, { workspace = "2", silent = true })
                hl.exec_cmd("slack --ozone-platform=wayland", { workspace = "special", silent = true })
                hl.exec_cmd("chromium", { workspace = "special", silent = true })
              end
            '')
          ];
        };

        config = {
          general = {
            gaps_in = 8;
            gaps_out = 16;
            border_size = 2;
            allow_tearing = true;
            col = {
              active_border = "rgb(${config.lib.stylix.colors.base0D})";
              inactive_border = "rgb(${config.lib.stylix.colors.base03})";
            };
          };

          decoration = {
            dim_special = lib.mkDefault 0.5;
            rounding = themeDetails.roundingRadius;
            shadow = {
              color = "rgba(${config.lib.stylix.colors.base00}99)";
            };
            blur = {
              enabled = lib.mkDefault false;
            };
          };

          animations = {
            enabled = true;
          };

          debug = {
            disable_logs = false;
          };

          input = {
            kb_layout = "us";
            kb_options = "grp:win_space_toggle";
            follow_mouse = true;
            touchpad = {
              natural_scroll = true;
              scroll_factor = 0.3;
              clickfinger_behavior = true;
            };
          };

          gestures = {
            workspace_swipe_distance = 200;
          };

          # dwindle = {
          #   # keep floating dimentions while tiling
          #   pseudotile = true;
          #   preserve_split = true;
          #   force_split = 2;
          #   split_width_multiplier = 1.5;
          # };

          master = {
            orientation = "center";
            mfact = 0.65;
          };

          ecosystem = {
            no_update_news = true;
            no_donation_nag = true;
          };

          group = {
            col = {
              border_active = "rgb(${config.lib.stylix.colors.base0D})";
              border_inactive = "rgb(${config.lib.stylix.colors.base03})";
              border_locked_active = "rgb(${config.lib.stylix.colors.base0C})";
            };
            groupbar = {
              col = {
                active = "rgb(${config.lib.stylix.colors.base0D})";
                inactive = "rgb(${config.lib.stylix.colors.base03})";
              };
              text_color = "rgb(${config.lib.stylix.colors.base05})";
            };
          };

          misc = {
            background_color = "rgb(${config.lib.stylix.colors.base00})";
            disable_hyprland_logo = true;
            force_default_wallpaper = 0;
            vrr = 3;
          };

          render = {
            direct_scanout = true;
          };

          xwayland = {
            force_zero_scaling = true;
          };
        };

        curve = [
          {
            _args = [
              "wind"
              {
                type = "bezier";
                points = [
                  [
                    0.05
                    0.9
                  ]
                  [
                    0.1
                    1.0
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "winIn"
              {
                type = "bezier";
                points = [
                  [
                    0.1
                    1.1
                  ]
                  [
                    0.1
                    1.03
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "winOut"
              {
                type = "bezier";
                points = [
                  [
                    0.3
                    (-0.3)
                  ]
                  [
                    0
                    1
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "liner"
              {
                type = "bezier";
                points = [
                  [
                    1
                    1
                  ]
                  [
                    1
                    1
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "workIn"
              {
                type = "bezier";
                points = [
                  [
                    0.72
                    (-0.07)
                  ]
                  [
                    0.41
                    0.98
                  ]
                ];
              }
            ];
          }
        ];

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 3;
            bezier = "wind";
            style = "slide";
          }
          {
            leaf = "windowsIn";
            enabled = true;
            speed = 3;
            bezier = "winIn";
            style = "slide";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 2;
            bezier = "winOut";
            style = "slide";
          }
          {
            leaf = "windowsMove";
            enabled = true;
            speed = 3;
            bezier = "wind";
            style = "slide";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 1;
            bezier = "liner";
          }
          {
            leaf = "borderangle";
            enabled = true;
            speed = 30;
            bezier = "liner";
            style = "loop";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 8;
            bezier = "default";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 2;
            bezier = "wind";
          }
          {
            leaf = "specialWorkspace";
            enabled = true;
            speed = 2;
            bezier = "workIn";
            style = "slidevert";
          }
        ];

        device = {
          name = "logitech-pro-x-2-1";
          sensitivity = -0.5;
        };
      }
      (lib.mkIf cfg.enableFancyEffects {
        config = {
          decoration = {
            dim_special = 0.2;
            shadow = lib.mkForce {
              enabled = false;
              range = 35;
              render_power = 3;
              color = "rgba(030a1430)";
              offset = "10 12";
              scale = 0.98;
            };
            blur = {
              enabled = true;
              size = 12;
              passes = 2;
              ignore_opacity = true;
              new_optimizations = true;
              xray = false;
              noise = 0.0117;
              contrast = 0.8916;
              brightness = 0.8172;
              vibrancy = 0.1696;
              vibrancy_darkness = 0.0;
              special = false;
              popups = true;
              popups_ignorealpha = 0.85;
            };
          };
        };
      })
    ];
  };
}
