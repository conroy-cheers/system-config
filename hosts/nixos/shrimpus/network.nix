{
  config,
  lib,
  pkgs,
  ...
}:
let
  supplicantSecrets = "/run/shrimpus-wifi/home.wifi.conf";
in
{
  age.secrets."home.wifi.conf" = {
    rekeyFile = ../../../secrets/master/home/wifi/conf.age;
    group = "wpa_supplicant";
    mode = "0440";
  };
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = false;
  networking.interfaces.wlan0.useDHCP = true;
  networking.wireless = {
    enable = true;
    interfaces = [ "wlan0" ];
    secretsFile = supplicantSecrets;
    extraConfig = "country=AU";
    networks = {
      "floznet-7".pskRaw = "ext:pass_home";
      "Abi_Wifi".pskRaw = "ext:pass_abi";
    };
  };

  # The shared secret is shell-quoted; wpa_supplicant's ext_password backend
  # needs unquoted key=value lines, as on panda.
  systemd.services.shrimpus-wifi-secrets = {
    description = "Prepare shrimpus Wi-Fi credentials";
    # agenix decrypts during activation, before these services start.
    before = [ "wpa_supplicant-wlan0.service" ];
    requiredBy = [ "wpa_supplicant-wlan0.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      . ${lib.escapeShellArg config.age.secrets."home.wifi.conf".path}
      install -d -m 0750 -o root -g wpa_supplicant /run/shrimpus-wifi
      tmp="$(mktemp /run/shrimpus-wifi/home.wifi.conf.XXXXXX)"
      trap 'rm -f "$tmp"' EXIT
      (
        umask 0077
        printf 'pass_home=%s\n' "''${pass_home:?}"
        printf 'pass_abi=%s\n' "''${pass_abi:?}"
      ) > "$tmp"
      chown root:wpa_supplicant "$tmp"
      chmod 0440 "$tmp"
      mv "$tmp" ${lib.escapeShellArg supplicantSecrets}
    '';
    path = [ pkgs.coreutils ];
  };

  systemd.services.wpa_supplicant-wlan0 = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };

  # A late SDIO device must start the service even if its boot-time job timed out.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="wpa_supplicant-wlan0.service"
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
