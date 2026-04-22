{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.panda;
  moonrakerStateDir = config.services.moonraker.stateDir;
  printerConfigDir = "${moonrakerStateDir}/config";
  gcodeDir = "${moonrakerStateDir}/gcodes";
  logDir = "${moonrakerStateDir}/logs";
  printerConfigFiles = [
    "mainsail.cfg"
    "sb2040v2.cfg"
    "stealthburner_leds.cfg"
  ];
in
{
  options.panda = {
    mockCan = lib.mkEnableOption "a virtual can0 device for VM smoke tests";

    webcam.enable = lib.mkEnableOption "the Mainsail /webcam/ endpoint";

    wifiSecretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional plaintext Wi-Fi env file used to bypass agenix in test-only configurations.";
    };
  };

  config = {
    networking.hostName = "panda";
    networking.extraHosts = ''
      127.0.0.1 panda.local
    '';

    time.timeZone = "Australia/Melbourne";

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    environment.systemPackages = with pkgs; [
      can-utils
      git
      tailscale
    ];

    boot.kernelModules = [
      "can"
      "can_raw"
      "gs_usb"
      "vcan"
    ];

    users.users.conroy = {
      isNormalUser = true;
      description = "Printer administrator";
      home = "/home/conroy";
      createHome = true;
      extraGroups = [
        "wheel"
        "dialout"
        "video"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKbNTRUenigTtrUSGKImYezWzT/KFOR7dZSpSuvsKNY"
      ];
      hashedPassword = "!";
    };

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    security.polkit.enable = true;

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        7125
      ];
    };

    services.tailscale.enable = true;

    services.klipper = {
      enable = true;
      mutableConfig = true;
      configDir = printerConfigDir;
      configFile = ./printer-config/printer.cfg;
      user = "moonraker";
      group = "moonraker";
    };

    services.moonraker = {
      enable = true;
      stateDir = "/var/lib/moonraker";
      address = "0.0.0.0";
      port = 7125;
      allowSystemControl = true;
      settings = {
        server.max_upload_size = 1024;
        file_manager.enable_object_processing = true;
        authorization = {
          cors_domains = [
            "https://panda.home.conroycheers.me"
            "http://*.local"
            "http://*.lan"
          ];
          trusted_clients = [
            "10.0.0.0/8"
            "127.0.0.0/8"
            "169.254.0.0/16"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "FE80::/10"
            "::1/128"
          ];
        };
        octoprint_compat = { };
        history = { };
        update_manager = {
          refresh_interval = 168;
          enable_system_updates = [ false ];
        };
      };
    };

    services.mainsail = {
      enable = true;
      hostName = "panda";
      nginx.serverAliases = [
        "panda.local"
        "panda.home.conroycheers.me"
      ];
    };

    services.nginx = {
      recommendedProxySettings = true;
      upstreams.mainsail-apiserver.servers = lib.mkForce {
        "127.0.0.1:${toString config.services.moonraker.port}" = { };
      };
    };

    services.mjpg-streamer = lib.mkIf cfg.webcam.enable {
      enable = true;
      inputPlugin = "input_uvc.so -d /dev/video0 -r 1280x720 -f 15";
      outputPlugin = "output_http.so -w @www@ -n -p 8080";
    };

    services.nginx.virtualHosts.${config.services.mainsail.hostName} = lib.mkIf cfg.webcam.enable {
      locations."/webcam/" = {
        proxyPass = "http://127.0.0.1:8080/";
        extraConfig = ''
          proxy_buffering off;
        '';
      };
    };

    systemd.tmpfiles.rules = [
      "d '/home/pi' 0755 root root - -"
      "d '${gcodeDir}' 0775 moonraker moonraker - -"
      "d '${logDir}' 0775 moonraker moonraker - -"
      "L+ '/home/pi/gcode_files' - - - - ${gcodeDir}"
      "L+ '/home/pi/klipper_config' - - - - ${printerConfigDir}"
      "L+ '/home/pi/printer_data' - - - - ${moonrakerStateDir}"
      "L+ '/home/pi/klipper_logs' - - - - ${logDir}"
    ];

    systemd.services.panda-printer-data-setup = {
      description = "Seed mutable printer config and state directories";
      before = [
        "klipper.service"
        "moonraker.service"
      ];
      requiredBy = [
        "klipper.service"
        "moonraker.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        let
          copyCommands = lib.concatMapStringsSep "\n" (
            file:
            let
              source = ./printer-config + "/${file}";
            in
            ''
              if [ ! -e ${printerConfigDir}/${file} ]; then
                install -D -m 0664 ${source} ${printerConfigDir}/${file}
              fi
            ''
          ) printerConfigFiles;
        in
        ''
          install -d -m 0775 -o moonraker -g moonraker ${printerConfigDir}
          install -d -m 0775 -o moonraker -g moonraker ${gcodeDir}
          install -d -m 0775 -o moonraker -g moonraker ${logDir}
          ${copyCommands}
          chown -R moonraker:moonraker ${moonrakerStateDir}
        '';
    };

    systemd.services.panda-can0 = {
      description = "Configure the Octopus-backed CAN network";
      before = [ "klipper.service" ];
      requiredBy = [ "klipper.service" ];
      after = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      path = with pkgs; [
        coreutils
        gnugrep
        iproute2
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ "${lib.boolToString cfg.mockCan}" = true ]; then
          ip link add dev can0 type vcan 2>/dev/null || true
          ip link set can0 txqueuelen 1024 || true
          ip link set can0 up
          exit 0
        fi

        for _ in $(seq 1 30); do
          if ip link show can0 >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        ip link show can0 >/dev/null 2>&1
        ip link set can0 down 2>/dev/null || true
        ip link set can0 type can bitrate 1000000
        ip link set can0 txqueuelen 1024
        ip link set can0 up
      '';
    };

    systemd.services.klipper = {
      after = [ "panda-can0.service" ];
      requires = [ "panda-can0.service" ];
    };

    system.stateVersion = "25.05";
  };
}
