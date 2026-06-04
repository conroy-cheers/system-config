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
in
{
  options = {
    corncheese.theming = {
      enable = lib.mkEnableOption "corncheese NixOS theming";
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

  imports = [ inputs.stylix.nixosModules.stylix ];

  config = lib.mkIf cfg.enable (
    let
      formatBase =
        name:
        let
          getComponent = comp: config.lib.stylix.colors."${name}-rgb-${comp}";
        in
        "${getComponent "r"},${getComponent "g"},${getComponent "b"}";
    in
    {
      corncheese.theming.themeDetails = themeDetails;

      warnings =
        lib.optional ((inputs.stylix.rev or null) != "525965744b770af79c985ae5c43c65e441dc8b29")
          "stylix input changed; re-check whether the local kmscon workaround in modules/nixos/corncheese-themes/default.nix is still required.";

      fonts = {
        fontconfig.enable = true;
        packages = [ config.stylix.fonts.monospace.package ];
      };

      services.kmscon.config = {
        "font-name" = config.stylix.fonts.monospace.name;
        "font-size" = config.stylix.fonts.sizes.terminal;
        palette = "custom";

        "palette-black" = formatBase "base00";
        "palette-red" = formatBase "base08";
        "palette-green" = formatBase "base0B";
        "palette-yellow" = formatBase "base0A";
        "palette-blue" = formatBase "base0D";
        "palette-magenta" = formatBase "base0E";
        "palette-cyan" = formatBase "base0C";
        "palette-light-grey" = formatBase "base05";
        "palette-dark-grey" = formatBase "base03";
        "palette-light-red" = formatBase "base08";
        "palette-light-green" = formatBase "base0B";
        "palette-light-yellow" = formatBase "base0A";
        "palette-light-blue" = formatBase "base0D";
        "palette-light-magenta" = formatBase "base0E";
        "palette-light-cyan" = formatBase "base0C";
        "palette-white" = formatBase "base07";

        "palette-background" = formatBase "base00";
        "palette-foreground" = formatBase "base05";
      };

      stylix = {
        enable = true;
        polarity = "dark";
        image = themeDetails.wallpaper;
        base16Scheme = lib.mkIf (
          cfg.theme != null
        ) "${pkgs.base16-schemes}/share/themes/${themeDetails.base16Scheme}.yaml";
        override = lib.mkIf (cfg.themeDetails.stylixOverride != null) cfg.themeDetails.stylixOverride;
        opacity = {
          terminal = cfg.themeDetails.opacity;
          applications = cfg.themeDetails.opacity;
          desktop = cfg.themeDetails.opacity;
          popups = cfg.themeDetails.opacity;
        };
        fonts = {
          sizes = {
            terminal = 11;
          };
        };

        targets.nvf.enable = lib.mkIf (cfg.theme != null) false;

        # https://github.com/nix-community/stylix/pull/2351
        targets.kmscon.enable = false;

        # targets.btop.enable =
        #   lib.mkIf (settings.themecfg.themeDetails.btopTheme != null) false;
      };
    }
  );

  meta = {
  };
}
