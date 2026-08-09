{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.silakka54;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "corncheese" "wm" "silakka54" "enable" ]
      [ "corncheese" "silakka54" "enable" ]
    )
  ];

  options.corncheese.silakka54.enable = lib.mkEnableOption "Silakka54 udev and hotplug synchronization";

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ pkgs.silakka54 ];
  };
}
