{
  lib,
  config,
  ...
}:
let
  cfg = config.panda;
  wifiSecret = ../../../secrets/master/home/wifi/conf.age;
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.wifiSecretsFile == null) {
      age.secrets."home.wifi.conf" = {
        rekeyFile = wifiSecret;
        group = "wpa_supplicant";
        mode = "440";
      };

      age.identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
      ];
    })

    {
      networking.useNetworkd = false;
      networking.useDHCP = false;
      networking.interfaces.end0.useDHCP = true;
      networking.interfaces.wlan0.useDHCP = true;

      networking.wireless = {
        enable = true;
        interfaces = [ "wlan0" ];
        userControlled = false;
        secretsFile =
          if cfg.wifiSecretsFile == null then config.age.secrets."home.wifi.conf".path else cfg.wifiSecretsFile;
        extraConfig = ''
          country=AU
        '';
        networks = {
          "floznet-7".pskRaw = "ext:FLOZNET_7_PSK";
          "Abi_Wifi".pskRaw = "ext:ABI_WIFI_PSK";
        };
      };

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };
    }
  ];
}
