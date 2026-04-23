{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.corncheese.theming;
  themeDetails = lib.recursiveUpdate (import (../../common + "/themes/${cfg.theme}.nix") {
    inherit pkgs;
  }) cfg.themeOverrides;
  colorshellEnabled = lib.attrByPath [ "programs" "colorshell" "enable" ] false config;
  walbridgePackage = inputs.walbridge.packages.${pkgs.stdenv.hostPlatform.system}.default;
  terminalTuiTransparent = themeDetails.terminalTuiTransparent or false;
  walbridgeApplyScript = pkgs.writeShellScript "walbridge-apply-runtime" ''
    set -euo pipefail

    palette_path="''${1:?usage: walbridge-apply-runtime <palette.json>}"
    normalized_palette="$palette_path"
    temp_palette=""

    if ! ${lib.getExe pkgs.jq} -e 'has("wallpaper")' "$palette_path" >/dev/null; then
      temp_palette="$(${lib.getExe' pkgs.coreutils "mktemp"})"
      ${lib.getExe pkgs.jq} \
        --arg wallpaper ${lib.escapeShellArg (toString themeDetails.wallpaper)} \
        '. + { wallpaper: $wallpaper }' \
        "$palette_path" >"$temp_palette"
      normalized_palette="$temp_palette"
    fi

    cleanup() {
      if [ -n "$temp_palette" ]; then
        rm -f "$temp_palette"
      fi
    }
    trap cleanup EXIT

    ${lib.getExe' walbridgePackage "walbridge"} apply --palette "$normalized_palette"

    hex_to_rgb() {
      local hex="''${1#\#}"
      printf '%d;%d;%d' "0x''${hex:0:2}" "0x''${hex:2:2}" "0x''${hex:4:2}"
    }

    background="$(${lib.getExe pkgs.jq} -r '.special.background // .colors.color0' "$palette_path")"
    foreground="$(${lib.getExe pkgs.jq} -r '.special.foreground // .colors.color7' "$palette_path")"
    red="$(${lib.getExe pkgs.jq} -r '.colors.color1' "$palette_path")"
    green="$(${lib.getExe pkgs.jq} -r '.colors.color2' "$palette_path")"
    yellow="$(${lib.getExe pkgs.jq} -r '.colors.color3' "$palette_path")"
    blue="$(${lib.getExe pkgs.jq} -r '.colors.color4' "$palette_path")"
    magenta="$(${lib.getExe pkgs.jq} -r '.colors.color5' "$palette_path")"
    cyan="$(${lib.getExe pkgs.jq} -r '.colors.color6' "$palette_path")"

    bg_rgb="$(hex_to_rgb "$background")"
    fg_rgb="$(hex_to_rgb "$foreground")"
    red_rgb="$(hex_to_rgb "$red")"
    green_rgb="$(hex_to_rgb "$green")"
    yellow_rgb="$(hex_to_rgb "$yellow")"
    blue_rgb="$(hex_to_rgb "$blue")"
    magenta_rgb="$(hex_to_rgb "$magenta")"
    cyan_rgb="$(hex_to_rgb "$cyan")"

    fish_terminal_palette="$HOME/.config/fish/conf.d/walbridge-terminal-palette.fish"
    cursor="$(${lib.getExe pkgs.jq} -r '.special.cursor // .special.foreground // .colors.color7' "$palette_path")"
    color0="''${background#\#}"
    color1="''${red#\#}"
    color2="''${green#\#}"
    color3="''${yellow#\#}"
    color4="''${blue#\#}"
    color5="''${magenta#\#}"
    color6="''${cyan#\#}"
    color7="''${foreground#\#}"
    color8="$(${lib.getExe pkgs.jq} -r '.colors.color8 // .colors.color0' "$palette_path")"
    color9="$(${lib.getExe pkgs.jq} -r '.colors.color9 // .colors.color1' "$palette_path")"
    color10="$(${lib.getExe pkgs.jq} -r '.colors.color10 // .colors.color2' "$palette_path")"
    color11="$(${lib.getExe pkgs.jq} -r '.colors.color11 // .colors.color3' "$palette_path")"
    color12="$(${lib.getExe pkgs.jq} -r '.colors.color12 // .colors.color4' "$palette_path")"
    color13="$(${lib.getExe pkgs.jq} -r '.colors.color13 // .colors.color5' "$palette_path")"
    color14="$(${lib.getExe pkgs.jq} -r '.colors.color14 // .colors.color6' "$palette_path")"
    color15="$(${lib.getExe pkgs.jq} -r '.colors.color15 // .colors.color7' "$palette_path")"
    color8="''${color8#\#}"
    color9="''${color9#\#}"
    color10="''${color10#\#}"
    color11="''${color11#\#}"
    color12="''${color12#\#}"
    color13="''${color13#\#}"
    color14="''${color14#\#}"
    color15="''${color15#\#}"
    cursor="''${cursor#\#}"

    cat >"$fish_terminal_palette" <<EOF
function __walbridge_restore_terminal_palette --on-event fish_prompt
    functions -e __walbridge_restore_terminal_palette
    if test "\$TERM" != dumb
        printf '\\e]4;0;rgb:''${color0:0:2}/''${color0:2:2}/''${color0:4:2}\\e\\\\'
        printf '\\e]4;1;rgb:''${color1:0:2}/''${color1:2:2}/''${color1:4:2}\\e\\\\'
        printf '\\e]4;2;rgb:''${color2:0:2}/''${color2:2:2}/''${color2:4:2}\\e\\\\'
        printf '\\e]4;3;rgb:''${color3:0:2}/''${color3:2:2}/''${color3:4:2}\\e\\\\'
        printf '\\e]4;4;rgb:''${color4:0:2}/''${color4:2:2}/''${color4:4:2}\\e\\\\'
        printf '\\e]4;5;rgb:''${color5:0:2}/''${color5:2:2}/''${color5:4:2}\\e\\\\'
        printf '\\e]4;6;rgb:''${color6:0:2}/''${color6:2:2}/''${color6:4:2}\\e\\\\'
        printf '\\e]4;7;rgb:''${color7:0:2}/''${color7:2:2}/''${color7:4:2}\\e\\\\'
        printf '\\e]4;8;rgb:''${color8:0:2}/''${color8:2:2}/''${color8:4:2}\\e\\\\'
        printf '\\e]4;9;rgb:''${color9:0:2}/''${color9:2:2}/''${color9:4:2}\\e\\\\'
        printf '\\e]4;10;rgb:''${color10:0:2}/''${color10:2:2}/''${color10:4:2}\\e\\\\'
        printf '\\e]4;11;rgb:''${color11:0:2}/''${color11:2:2}/''${color11:4:2}\\e\\\\'
        printf '\\e]4;12;rgb:''${color12:0:2}/''${color12:2:2}/''${color12:4:2}\\e\\\\'
        printf '\\e]4;13;rgb:''${color13:0:2}/''${color13:2:2}/''${color13:4:2}\\e\\\\'
        printf '\\e]4;14;rgb:''${color14:0:2}/''${color14:2:2}/''${color14:4:2}\\e\\\\'
        printf '\\e]4;15;rgb:''${color15:0:2}/''${color15:2:2}/''${color15:4:2}\\e\\\\'
        printf '\\e]10;rgb:''${color7:0:2}/''${color7:2:2}/''${color7:4:2}\\e\\\\'
        printf '\\e]11;rgb:''${color0:0:2}/''${color0:2:2}/''${color0:4:2}\\e\\\\'
        printf '\\e]12;rgb:''${cursor:0:2}/''${cursor:2:2}/''${cursor:4:2}\\e\\\\'
    end
end
EOF

    if [ "${if terminalTuiTransparent then "1" else "0"}" = "1" ]; then
      btop_theme="$HOME/.config/btop/themes/walbridge.theme"
      if [ -f "$btop_theme" ]; then
        ${lib.getExe pkgs.gnused} -i 's|^theme\[main_bg\]=.*$|theme[main_bg]=""|' "$btop_theme"
      fi
    fi
  '';
  walbridgeGhosttyPlaceholder = ''
    background = 11111b
    foreground = cdd6f4
    cursor-color = cdd6f4
    selection-background = 313244
    selection-foreground = cdd6f4
    palette = 0=11111b
    palette = 1=f38ba8
    palette = 2=a6e3a1
    palette = 3=f9e2af
    palette = 4=89b4fa
    palette = 5=cba6f7
    palette = 6=94e2d5
    palette = 7=cdd6f4
    palette = 8=45475a
    palette = 9=f38ba8
    palette = 10=a6e3a1
    palette = 11=f9e2af
    palette = 12=89b4fa
    palette = 13=cba6f7
    palette = 14=94e2d5
    palette = 15=f5e0dc
  '';
  walbridgeBatPlaceholder = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>name</key>
        <string>Walbridge</string>
        <key>settings</key>
        <array>
          <dict>
            <key>settings</key>
            <dict>
              <key>background</key>
              <string>#11111b</string>
              <key>foreground</key>
              <string>#cdd6f4</string>
              <key>caret</key>
              <string>#cdd6f4</string>
              <key>selection</key>
              <string>#313244</string>
            </dict>
          </dict>
        </array>
      </dict>
    </plist>
  '';
  walbridgeWeztermPlaceholder = ''
    return {
      color_scheme = "walbridge",
      color_schemes = {
        walbridge = {
          ansi = { "#11111b", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#cdd6f4" },
          brights = { "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#cba6f7", "#94e2d5", "#f5e0dc" },
          background = "#11111b",
          cursor_bg = "#cdd6f4",
          cursor_fg = "#11111b",
          compose_cursor = "#f5e0dc",
          foreground = "#cdd6f4",
        },
      },
    }
  '';
  walbridgeFishPlaceholder = ''
    set -g fish_color_normal cdd6f4
    set -g fish_color_command 89b4fa
    set -g fish_color_keyword cba6f7
    set -g fish_color_quote a6e3a1
    set -g fish_color_redirection 94e2d5
    set -g fish_color_end fab387
    set -g fish_color_error f38ba8
    set -g fish_color_param cdd6f4
    set -g fish_color_comment 45475a
    set -g fish_color_autosuggestion 45475a
    set -g fish_color_selection --background=313244
  '';
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese theming";
      theme = lib.mkOption {
        type = with lib.types; str;
        description = "Theme to use";
      };
      themeOverrides = lib.mkOption {
        type = with lib.types; anything;
        description = "Overrides for imported theme data";
        default = { };
      };
      themeDetails = lib.mkOption {
        type = with lib.types; anything;
        description = "Imported theme data";
        readOnly = true;
      };
      walbridgeApplyCommand = lib.mkOption {
        type = with lib.types; package;
        description = "Runtime walbridge apply helper used by colorshell and activation.";
        readOnly = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    corncheese.theming.themeDetails = themeDetails;
    corncheese.theming.walbridgeApplyCommand = walbridgeApplyScript;

    stylix = {
      enable = true;
      polarity = "dark";
      image = themeDetails.wallpaper;
      base16Scheme = lib.mkIf (
        cfg.theme != null
      ) "${pkgs.base16-schemes}/share/themes/${themeDetails.base16Scheme}.yaml";
      override = lib.mkIf (themeDetails.stylixOverride != null) themeDetails.stylixOverride;
      opacity = {
        terminal = themeDetails.opacity;
        applications = themeDetails.opacity;
        desktop = themeDetails.opacity;
        popups = themeDetails.opacity;
      };
      fonts = {
        sizes = {
          terminal = themeDetails.fontSize;
        };
      };

      targets.nvf.enable = lib.mkIf (cfg.theme != null) false;

      targets.vscode.profileNames = [ "default" ];
      targets.firefox.profileNames = [ "default" ];
      targets.gtk.enable = lib.mkIf colorshellEnabled false;
      targets.qt.enable = lib.mkIf colorshellEnabled false;
      targets.vscode.enable = lib.mkIf colorshellEnabled false;
      targets.btop.enable = lib.mkIf colorshellEnabled false;
      targets.bat.enable = lib.mkIf colorshellEnabled false;
      targets.ghostty.enable = lib.mkIf colorshellEnabled false;
      targets.fish.enable = lib.mkIf colorshellEnabled false;
      targets.wezterm.enable = lib.mkIf colorshellEnabled false;
    };

    programs.bat.config.theme = lib.mkIf colorshellEnabled "walbridge";
    programs.btop.settings.color_theme = lib.mkIf colorshellEnabled "walbridge";
    programs.ghostty.settings.theme = lib.mkIf colorshellEnabled "walbridge";

    home.sessionVariables = lib.mkIf colorshellEnabled {
      WALBRIDGE_TERMINAL_TUI_TRANSPARENT = if terminalTuiTransparent then "1" else "0";
    };

    home.activation.ensureWalbridgeThemePlaceholders = lib.mkIf colorshellEnabled (
      lib.hm.dag.entryBefore [ "batCache" "onFilesChange" ] ''
        ghostty_theme="$HOME/.config/ghostty/themes/walbridge"
        bat_theme="$HOME/.config/bat/themes/walbridge.tmTheme"
        wezterm_theme="$HOME/.config/wezterm/walbridge.lua"
        fish_theme="$HOME/.config/fish/conf.d/walbridge.fish"
        fish_ls_colors="$HOME/.config/fish/conf.d/walbridge-ls-colors.fish"
        starship_template="$HOME/.config/starship.toml"
        starship_runtime="$HOME/.config/starship-walbridge.toml"

        mkdir -p \
          "$(dirname "$ghostty_theme")" \
          "$(dirname "$bat_theme")" \
          "$(dirname "$wezterm_theme")" \
          "$(dirname "$fish_theme")"

        if [ ! -e "$ghostty_theme" ]; then
          cat >"$ghostty_theme" <<'EOF'
${walbridgeGhosttyPlaceholder}
EOF
        fi

        if [ ! -e "$bat_theme" ]; then
          cat >"$bat_theme" <<'EOF'
${walbridgeBatPlaceholder}
EOF
        fi

        if [ ! -e "$wezterm_theme" ]; then
          cat >"$wezterm_theme" <<'EOF'
${walbridgeWeztermPlaceholder}
EOF
        fi

        if [ ! -e "$fish_theme" ]; then
          cat >"$fish_theme" <<'EOF'
${walbridgeFishPlaceholder}
EOF
        fi

        rm -f "$fish_ls_colors"

        if [ ! -e "$starship_runtime" ] && [ -e "$starship_template" ]; then
          cp "$starship_template" "$starship_runtime"
        fi

        wal_palette="$HOME/.cache/wal/colors.json"
        if [ -e "$wal_palette" ]; then
          if ! ${lib.getExe pkgs.jq} -e 'has("wallpaper")' "$wal_palette" >/dev/null; then
            tmp_palette="$(${lib.getExe' pkgs.coreutils "mktemp"})"
            ${lib.getExe pkgs.jq} \
              --arg wallpaper ${lib.escapeShellArg (toString themeDetails.wallpaper)} \
              '. + { wallpaper: $wallpaper }' \
              "$wal_palette" >"$tmp_palette"
            mv "$tmp_palette" "$wal_palette"
          fi

          ${walbridgeApplyScript} "$wal_palette"
        fi
      ''
    );
  };

  meta = {
  };
}
