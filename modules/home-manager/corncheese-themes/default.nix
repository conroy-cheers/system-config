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

    ${lib.getExe' walbridgePackage "walbridge"} apply --palette "$palette_path"

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

        if [ ! -e "$starship_runtime" ] && [ -e "$starship_template" ]; then
          cp "$starship_template" "$starship_runtime"
        fi

        wal_palette="$HOME/.cache/wal/colors.json"
        if [ -e "$wal_palette" ]; then
          ${walbridgeApplyScript} "$wal_palette"
        fi
      ''
    );
  };

  meta = {
  };
}
