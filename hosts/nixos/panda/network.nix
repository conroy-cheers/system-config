{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.panda;
  wifiSecret = ../../../secrets/master/home/wifi/conf.age;
  sourceWifiSecretsFile =
    if cfg.wifiSecretsFile == null then
      config.age.secrets."home.wifi.conf".path
    else
      cfg.wifiSecretsFile;
  supplicantWifiSecretsFile = "/run/panda-wifi/home.wifi.conf";
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
      networking.dhcpcd.extraConfig = ''
        interface end0
        hostname panda-eth

        interface wlan0
        hostname panda
      '';

      networking.wireless = {
        enable = true;
        interfaces = [ "wlan0" ];
        userControlled = false;
        secretsFile = supplicantWifiSecretsFile;
        extraConfig = ''
          country=AU
        '';
        networks = {
          "floznet-7".pskRaw = "ext:pass_home";
          "Abi_Wifi".pskRaw = "ext:pass_abi";
        };
      };

      systemd.services.panda-wifi-secrets = {
        description = "Prepare panda Wi-Fi secrets for wpa_supplicant";
        before = [ "wpa_supplicant-wlan0.service" ];
        requiredBy = [ "wpa_supplicant-wlan0.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          . ${lib.escapeShellArg sourceWifiSecretsFile}

          ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g wpa_supplicant /run/panda-wifi
          tmp="$(${pkgs.coreutils}/bin/mktemp /run/panda-wifi/home.wifi.conf.XXXXXX)"
          (
            umask 0077
            printf 'pass_home=%s\n' "''${pass_home:?}"
            printf 'pass_abi=%s\n' "''${pass_abi:?}"
          ) > "$tmp"
          ${pkgs.coreutils}/bin/chown root:wpa_supplicant "$tmp"
          ${pkgs.coreutils}/bin/chmod 0440 "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg supplicantWifiSecretsFile}
        '';
      };

      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };
    }
  ];
}
