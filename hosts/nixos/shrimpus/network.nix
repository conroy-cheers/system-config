{
  config,
  lib,
  pkgs,
  ...
}:
{
  age.secrets."home.wifi.conf" = {
    rekeyFile = ../../../secrets/master/home/wifi/conf.age;
    mode = "0400";
  };
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = false;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=AU
  '';
  networking.networkmanager = {
    enable = true;
    package = pkgs.shrimpus-networkmanager;
    wifi.backend = "wpa_supplicant";
    ensureProfiles = {
      environmentFiles = [ config.age.secrets."home.wifi.conf".path ];
      profiles = {
        floznet-7 = {
          connection = {
            id = "floznet-7";
            type = "wifi";
            uuid = "e6998662-543b-4b85-84e2-f0f74f43d4d2";
            interface-name = "wlan0";
            autoconnect = true;
            autoconnect-priority = 20;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "floznet-7";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$pass_home";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
        Abi_Wifi = {
          connection = {
            id = "Abi_Wifi";
            type = "wifi";
            uuid = "28e89fd0-fd59-4d57-bc06-3c879675f8b8";
            interface-name = "wlan0";
            autoconnect = true;
            autoconnect-priority = 10;
          };
          wifi = {
            mode = "infrastructure";
            ssid = "Abi_Wifi";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$pass_abi";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };
  networking.modemmanager.enable = false;
  security.polkit.enable = lib.mkForce false;
  systemd.services.NetworkManager-wait-online.enable = false;

  # A late SDIO device must wake the network manager after it appears.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="NetworkManager.service"
  '';

  systemd.services.shrimpus-wifi-health = {
    description = "Check Wi-Fi interface and retry an unbound UWE5622 device";
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "shrimpus-wifi-health";
      RuntimeDirectoryPreserve = true;
      TimeoutStartSec = "45s";
    };
    path = [
      pkgs.coreutils
      pkgs.systemd
    ];
    script = builtins.readFile ./wifi-health.sh;
  };
  systemd.timers.shrimpus-wifi-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "45s";
      OnUnitActiveSec = "60s";
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
}
