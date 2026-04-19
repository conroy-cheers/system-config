{
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
  walbridgeGhosttyPlaceholder = with config.lib.stylix.colors.withHashtag; ''
    background = ${base00}
    foreground = ${base05}
    cursor-color = ${base05}
    selection-background = ${base02}
    selection-foreground = ${base05}
    palette = 0=${base00}
    palette = 1=${base08}
    palette = 2=${base0B}
    palette = 3=${base0A}
    palette = 4=${base0D}
    palette = 5=${base0E}
    palette = 6=${base0C}
    palette = 7=${base05}
    palette = 8=${base03}
    palette = 9=${base08}
    palette = 10=${base0B}
    palette = 11=${base0A}
    palette = 12=${base0D}
    palette = 13=${base0E}
    palette = 14=${base0C}
    palette = 15=${base07}
  '';
  walbridgeBatPlaceholder = with config.lib.stylix.colors.withHashtag; ''
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
              <string>${base00}</string>
              <key>foreground</key>
              <string>${base05}</string>
              <key>caret</key>
              <string>${base05}</string>
              <key>selection</key>
              <string>${base02}</string>
            </dict>
          </dict>
        </array>
      </dict>
    </plist>
  '';
  walbridgeWeztermPlaceholder = with config.lib.stylix.colors.withHashtag; ''
    return {
      color_scheme = "walbridge",
      color_schemes = {
        walbridge = {
          ansi = { "${base00}", "${base08}", "${base0B}", "${base0A}", "${base0D}", "${base0E}", "${base0C}", "${base05}" },
          brights = { "${base03}", "${base08}", "${base0B}", "${base0A}", "${base0D}", "${base0E}", "${base0C}", "${base07}" },
          background = "${base00}",
          cursor_bg = "${base05}",
          cursor_fg = "${base00}",
          compose_cursor = "${base07}",
          foreground = "${base05}",
        },
      },
    }
  '';
  walbridgeFishPlaceholder = with config.lib.stylix.colors; ''
    set -g fish_color_normal ${base05}
    set -g fish_color_command ${base0D}
    set -g fish_color_keyword ${base0E}
    set -g fish_color_quote ${base0B}
    set -g fish_color_redirection ${base0C}
    set -g fish_color_end ${base09}
    set -g fish_color_error ${base08}
    set -g fish_color_param ${base05}
    set -g fish_color_comment ${base03}
    set -g fish_color_autosuggestion ${base03}
    set -g fish_color_selection --background=${base02}
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
    };
  };

  config = lib.mkIf cfg.enable {
    corncheese.theming.themeDetails = themeDetails;

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
      ''
    );
  };

  meta = {
  };
}
