{ inputs, lib, pkgs, config, ... }:
{
  environment.systemPackages = with pkgs; [
  ];

  networking.extraHosts = ''
    127.0.0.1 kombu.local
  '';

  age.secrets."home.wifi.env" = {
    rekeyFile = "${inputs.self}/secrets/home/wifi/env.age";
  };
  networking.wireless = {
    enable = true;
    environmentFile = config.age.secrets."home.wifi.env".path;
    networks = {
      "@HOME_WIFI_SSID@" = {
        psk = "@HOME_WIFI_PSK@";
        priority = 20;
      };
      "@ANDROMEDA_WIFI_SSID@" = {
        psk = "@ANDROMEDA_WIFI_PSK@";
        priority = 10;
      };
      "@ABI_WIFI_SSID@" = {
        psk = "@ABI_WIFI_PSK@";
      };
    };
  };
  networking.useNetworkd = false;

  systemd.network.enable = false;
  systemd.network.networks = {
    "10-enp5s0" = {
      DHCP = "yes";
      matchConfig.MACAddress = "00:e0:1f:bd:81:cb";
      networkConfig = {
        IPv6PrivacyExtensions = "yes";
        MulticastDNS = true;
      };
      dhcpV4Config.RouteMetric = 10;
      dhcpV6Config.RouteMetric = 10;
    };

    "15-wlan0" = {
      DHCP = "yes";
      matchConfig.MACAddress = "6c:2f:80:e0:ce:2d";
      networkConfig = {
        IPv6PrivacyExtensions = "yes";
        MulticastDNS = true;
      };
    };
  };

  # systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
}
