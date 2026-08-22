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
  walbridgePackages = inputs.walbridge.packages.${pkgs.stdenv.hostPlatform.system};
  walbridgePackage = walbridgePackages.default;
  walbridgeExtractPackage = walbridgePackages.walbridge-extract;
  walbridgeVisualizePackage = walbridgePackages.walbridge-visualize;
  walbridgeColors = builtins.fromJSON (
    builtins.readFile (
      pkgs.runCommand "walbridge-colors.json" { } ''
        export HOME="$TMPDIR"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        ${lib.getExe' walbridgeExtractPackage "walbridge-extract"} \
          --image ${lib.escapeShellArg (toString themeDetails.wallpaper)} \
          --colors-out "$TMPDIR/colors.json" \
          --palette-out "$TMPDIR/palette.json"
        ${lib.getExe pkgs.jq} 'del(.wallpaper)' "$TMPDIR/colors.json" >"$out"
      ''
    )
  );
  colorshellPackage = inputs.colorshell.packages.${pkgs.stdenv.hostPlatform.system}.colorshell;
  colorshellHyprlockTemplate = with config.lib.stylix.colors; ''
    source = ~/.cache/wal/colors-hyprland.conf

    background {
      monitor =
      color = rgb(${base00})
      path = $wallpaper
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
    home.packages = [
      walbridgePackage
      walbridgeExtractPackage
      walbridgeVisualizePackage
      pkgs.hyprlock
      pkgs.libsForQt5.qt5ct
      pkgs.qt6Packages.qt6ct
    ];

    home.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt5ct";
      QT_STYLE_OVERRIDE = "Fusion";
    };

    stylix.targets = {
      hyprland.hyprpaper.enable = false;
      hyprpaper.enable = false;
    };

    programs.colorshell = {
      package = colorshellPackage;
      settings = {
        color = {
          engine = "static";
          static =
            let
              bgPrimary = "oklch(from ${walbridgeColors.colors.color1} calc(l - .36) c h)";
              bgSecondary = "oklch(from ${walbridgeColors.colors.color1} calc(l - .22) c h)";
              bgTertiary = "oklch(from ${walbridgeColors.colors.color1} calc(l - .1) c h)";
            in
            {
              bg_primary = bgPrimary;
              bg_secondary = bgSecondary;
              bg_tertiary = bgTertiary;
              bg_translucent_primary = "oklch(from ${bgPrimary} l c h / .68)";
              bg_translucent_secondary = "oklch(from ${bgSecondary} l c h / .68)";
              bg_translucent_tertiary = "oklch(from ${bgTertiary} l c h / .68)";
              fg_primary = walbridgeColors.special.foreground;
              fg_disabled = "oklch(from ${walbridgeColors.special.foreground} calc(l - .10) c h)";
            };
        };

        misc.match_window_border_color = false;
      };
    };

    programs.hyprlock.extraConfig = colorshellHyprlockTemplate;
  };
}
