{ lib, pkgs, ... }:

let
  # The dashboard glyphs are embedded at build time, but Slint's font backend
  # still requires one discoverable fallback while it initializes.
  dashboardFontconfig = pkgs.writeText "shrimpus-dashboard-fontconfig.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${pkgs.shrimpus-dashboard}/share/fonts/truetype</dir>
      <cachedir>/var/cache/shrimpus-dashboard/fontconfig</cachedir>
    </fontconfig>
  '';
in

{
  users.groups.shrimpus-dashboard = { };
  users.users.shrimpus-dashboard = {
    isSystemUser = true;
    group = "shrimpus-dashboard";
    extraGroups = [ "video" ];
  };

  systemd.services.shrimpus-dashboard = {
    description = "Shrimpus e-paper dashboard";
    wants = [ "NetworkManager.service" ];
    after = [ "NetworkManager.service" ];
    environment = {
      FONTCONFIG_FILE = dashboardFontconfig;
      SLINT_BACKEND = "linuxkms-software";
      SHRIMPUS_WEATHER_CACHE = "/var/cache/shrimpus-dashboard/weather.json";
      SHRIMPUS_WEATHER_LATITUDE = "-37.8136";
      SHRIMPUS_WEATHER_LONGITUDE = "144.9631";
      SHRIMPUS_WEATHER_TIMEZONE = "Australia/Melbourne";
    };
    serviceConfig = {
      ExecStart = lib.getExe pkgs.shrimpus-dashboard;
      Restart = "always";
      RestartSec = "15s";

      User = "shrimpus-dashboard";
      Group = "shrimpus-dashboard";
      SupplementaryGroups = [ "video" ];
      CacheDirectory = "shrimpus-dashboard";
      UMask = "0077";

      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/dri/card0 rw" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };

  # A .device dependency never becomes active for this DRM character node and
  # would hold multi-user.target open.  A path unit starts the service once the
  # node exists, before DeviceAllow is resolved for the service sandbox.
  systemd.paths.shrimpus-dashboard = {
    description = "Watch for the Shrimpus e-paper DRM device";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExists = "/dev/dri/card0";
  };
}
