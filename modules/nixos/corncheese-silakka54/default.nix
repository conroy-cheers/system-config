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

    systemd.services.silakka54-hotplug = {
      description = "Sync Silakka54 dynamic keymap after keyboard hotplug";
      after = [ "systemd-udevd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.silakka54} hotplug";
      };
      path = [ pkgs.systemd ];
    };

    system.activationScripts.silakka54-udev-trigger.text = ''
      ${pkgs.systemd}/bin/udevadm control --reload-rules || true
      ${pkgs.systemd}/bin/udevadm trigger \
        --subsystem-match=hidraw \
        --property-match=ID_VENDOR_ID=feed \
        --property-match=ID_MODEL_ID=1212 \
        --action=change || true
      ${pkgs.systemd}/bin/udevadm trigger \
        --subsystem-match=input \
        --property-match=ID_VENDOR_ID=feed \
        --property-match=ID_MODEL_ID=1212 \
        --action=change || true
    '';
  };
}
