{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  environment.systemPackages = with pkgs; [ ];

  networking.extraHosts = ''
    127.0.0.1 kombu.local
  '';

  age.secrets."home.wifi.conf" = {
    rekeyFile = lib.repoSecret "home/wifi/conf.age";
  };
  networking.wireless = {
    # enable = true;
    userControlled.enable = true;
    secretsFile = config.age.secrets."home.wifi.conf".path;
    networks = {
      "ext:ssid_home" = {
        psk = "ext:pass_home";
        priority = 20;
      };
      "ext:ssid_andromeda" = {
        psk = "ext:pass_andromeda";
        priority = 10;
      };
      "ext:ssid_abi" = {
        psk = "ext:pass_abi";
      };
    };
  };
  networking.useNetworkd = false;

  networking.networkmanager.enable = true;

  # enable mDNS
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # systemd.network.enable = false;
  # systemd.network.networks = {
  #   "10-enp5s0" = {
  #     DHCP = "yes";
  #     matchConfig.MACAddress = "00:e0:1f:bd:81:cb";
  #     networkConfig = {
  #       IPv6PrivacyExtensions = "yes";
  #       MulticastDNS = true;
  #     };
  #     dhcpV4Config.RouteMetric = 10;
  #     dhcpV6Config.RouteMetric = 10;
  #   };

  #   "15-wlan0" = {
  #     DHCP = "yes";
  #     matchConfig.MACAddress = "6c:2f:80:e0:ce:2d";
  #     networkConfig = {
  #       IPv6PrivacyExtensions = "yes";
  #       MulticastDNS = true;
  #     };
  #   };
  # };

  # systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
}
