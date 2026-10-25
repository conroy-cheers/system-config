{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.corncheese.wm;
  colorshellEnabled = lib.attrByPath [ "programs" "colorshell" "enable" ] false config;
  themeDetails = config.corncheese.theming.themeDetails;
  colorshellPackage =
    (inputs.colorshell.packages.${pkgs.stdenv.hostPlatform.system}.colorshell.override (args: {
      pywal = pkgs.pywal16;
      # Patch Colorshell's own Astal dependency; a consumer pkgs overlay does
      # not change the package exported by the Colorshell flake.
      astal = args.astal // {
        hyprland = args.astal.hyprland.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./astal-hyprland-workspace-address.patch ];
        });
      };
    })).overrideAttrs
      (oldAttrs: {
        src = oldAttrs.src.overrideAttrs (oldSrc: {
          patches = (oldSrc.patches or [ ]) ++ [ ./colorshell-first-run-write.patch ];
          # The launcher now sets LD_PRELOAD on the command instead of exporting
          # it. Patch the library path independently of that shell syntax.
          postPatch = ''
            substituteInPlace scripts/build.sh \
              --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe pkgs.bash}' \
              --replace-fail '#!/usr/bin/env -S gjs -m' '#!${lib.getExe pkgs.gjs} -m' \
              --replace-fail '/usr/lib/libgtk4-layer-shell.so' '${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so'
            substituteInPlace src/modules/wallpaper.ts \
              --replace-fail '/usr/share/hypr/wall2.png' '${themeDetails.wallpaper}'
          '';
        });

        # The bundled launcher base64-encodes the generated GJS program, which
        # hides its interpreter store path from Nix's runtime reference scan.
        # Keep GJS in the package closure so garbage collection cannot leave
        # the launcher with a dangling shebang.
        postFixup = (oldAttrs.postFixup or "") + ''
          mkdir -p $out/libexec
          ln -s ${pkgs.gjs} $out/libexec/gjs
        '';
      });
  wallpaperConfig = pkgs.writeText "colorshell-theme-hyprpaper.conf" ''
    splash = false
    wallpaper {
      monitor = *
      path = ${themeDetails.wallpaper}
      fit_mode = cover
    }
  '';
  wallpaperMarker = pkgs.writeText "colorshell-theme-wallpaper" "${themeDetails.wallpaper}\n";
  colorshellHyprlockTemplate = with config.lib.stylix.colors; ''
    background {
      monitor =
      color = rgb(${base00})
      path = ${themeDetails.wallpaper}
    }

    general {
      grace = 0
      ignore_empty_input = true
    }

    input-field {
      monitor =
      size = 250, 50
      outline_thickness = 0
      dots_size = 0.26
      dots_spacing = 0.64
      dots_center = true
      fade_on_empty = true
      placeholder_text = <i>Password...</i>
      hide_input = false
      check_color = rgb(${base0A})
      fail_color = rgb(${base08})
      font_color = rgb(${base05})
      inner_color = rgb(${base00})
      outer_color = rgb(${base03})
      position = 0, 50
      halign = center
      valign = bottom
    }

    label {
        monitor =
        text = cmd[update:1000] echo "<b><big> $(date +"%H:%M") </big></b>"
        color = rgba(${base00-rgb-r}, ${base00-rgb-g}, ${base00-rgb-b}, 0.7)

        font_size = 108
        font_family = MesloLGM Nerd Font Propo

        position = 0, 310
        halign = center
        valign = center

        shadow_passes = 4
        shadow_size = 4
        shadow_boost = 0.2
    }

    label {
        monitor =
        text = cmd[update:18000000] echo "<b> "$(date +'%A, %-d %B %Y')" </b>"
        color = rgba(${base00-rgb-r}, ${base00-rgb-g}, ${base00-rgb-b}, 0.7)

        font_size = 24
        font_family = MesloLGM Nerd Font Propo

        position = 0, 215
        halign = center
        valign = center

        shadow_passes = 4
        shadow_size = 4
        shadow_boost = 0.8
    }
  '';
in
{
  config = lib.mkIf (cfg.enable && colorshellEnabled) {
    stylix.targets = {
      hyprland.hyprpaper.enable = false;
      hyprpaper.enable = false;
      hyprlock.enable = false;
    };

    programs.colorshell = {
      package = colorshellPackage;
      hyprlock.enable = lib.mkIf (cfg.sessionMode == "nested") false;
      hyprsunset.enable = lib.mkIf (cfg.sessionMode == "nested") false;
      settings = {
        color = {
          engine = "static";
          static = with config.lib.stylix.colors.withHashtag; {
            bg_primary = base00;
            bg_secondary = base01;
            bg_tertiary = base02;
            bg_translucent_primary = "oklch(from ${base00} l c h / .68)";
            bg_translucent_secondary = "oklch(from ${base01} l c h / .68)";
            bg_translucent_tertiary = "oklch(from ${base02} l c h / .68)";
            fg_primary = base05;
            fg_disabled = base04;
          };
        };

        aliases = {
          terminal = cfg.terminal;
          file_manager = "thunar";
        };
        misc.match_window_border_color = false;
      };
    };

    # Colorshell edits hyprpaper.conf itself, so seed a writable config rather
    # than installing an immutable Home Manager symlink. Follow theme updates
    # only while the previous theme wallpaper remains selected.
    home.activation.colorshellWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      wallpaper_config=${lib.escapeShellArg "${config.xdg.configHome}/hypr/hyprpaper.conf"}
      wallpaper_state=${lib.escapeShellArg "${config.xdg.stateHome}/colorshell/theme-wallpaper"}
      previous_wallpaper=""
      current_wallpaper=""
      if [[ -f "$wallpaper_state" ]]; then
        previous_wallpaper=$(cat "$wallpaper_state")
      fi
      if [[ -f "$wallpaper_config" ]]; then
        current_wallpaper=$(${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$wallpaper_config" | head -n 1)
      fi
      if [[ ! -L "$wallpaper_config" ]] && {
        [[ ! -e "$wallpaper_config" ]] ||
        [[ -n "$previous_wallpaper" && "$current_wallpaper" == "$previous_wallpaper" ]] ||
        [[ "$current_wallpaper" == "${pkgs.hyprland}/share/hypr/wall2.png" ]];
      }; then
        run mkdir -p "$(dirname "$wallpaper_config")" "$(dirname "$wallpaper_state")"
        run install -m 600 ${wallpaperConfig} "$wallpaper_config"
        run install -m 600 ${wallpaperMarker} "$wallpaper_state"
      fi
    '';

    programs.hyprlock.extraConfig = lib.mkIf (cfg.sessionMode == "login") colorshellHyprlockTemplate;

    # Nested services run in the compositor's private bus/runtime and cgroup.
    # Keep the shared shell configuration, but disable login-target autostart.
    systemd.user.services = lib.mkIf (cfg.sessionMode == "nested") {
      colorshell.Install.WantedBy = lib.mkForce [ ];
      hyprpaper.Install.WantedBy = lib.mkForce [ ];
    };
  };
}
