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
  userPasswordSecret = ../../../secrets/master/home/conroy/user/password.age;
  turnHost = "turn.home.conroycheers.me";
  turnUser = "panda-webrtc";
  turnCredential = "vnrGVsjHTMEsJlmYvoLXCUeq";
  printerConfigFiles = [
    "mainsail.cfg"
    "sb2040v2.cfg"
    "stealthburner_leds.cfg"
  ];
in
{
  options.panda = {
    can.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the physical Octopus CAN interface is attached and Klipper should start.";
    };

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
      trusted-users = [
        "root"
        "conroy"
      ];
    };

    environment.systemPackages = with pkgs; [
      can-utils
      camera-streamer
      git
      libcamera
      tailscale
      v4l-utils
    ];

    boot.kernelModules = [
      "can"
      "can_raw"
      "gs_usb"
      "vcan"
    ];

    age.secrets."conroy.user.password" = {
      rekeyFile = userPasswordSecret;
      mode = "440";
    };

    users.groups.i2c = { };

    services.udev.extraRules = ''
      SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
      ACTION=="add", SUBSYSTEM=="net", KERNEL=="can0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="panda-can0.service"
    '';

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
      hashedPasswordFile = config.age.secrets."conroy.user.password".path;
      shell = pkgs.fish;
    };

    programs.fish.enable = true;

    systemd.targets.getty.wants = [ "serial-getty@ttyS0.service" ];

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ "conroy" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

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
      enable = cfg.can.enable;
      mutableConfig = true;
      configDir = printerConfigDir;
      configFile = ./printer-config/printer.cfg;
      user = "moonraker";
      group = "moonraker";
      firmwares = {
        mcu = {
          enable = true;
          configFile = ./firmware-configs/octopus-klipper.config;
        };
        SB2040v2 = {
          enable = true;
          configFile = ./firmware-configs/sb2040-klipper.config;
        };
      };
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
        "webcam chamber" = lib.mkIf cfg.webcam.enable {
          location = "printer";
          icon = "mdiWebcam";
          enabled = true;
          service = "webrtc-camerastreamer";
          target_fps = 30;
          target_fps_idle = 5;
          stream_url = "/webcam/webrtc";
          snapshot_url = "/webcam/?action=snapshot";
          aspect_ratio = "16:9";
        };
        update_manager = {
          refresh_interval = 168;
          enable_system_updates = [ false ];
        };
      };
    };

    systemd.services.moonraker.restartTriggers = [
      (pkgs.writeText "moonraker-settings.json" (builtins.toJSON config.services.moonraker.settings))
    ];

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

    systemd.services.camera-streamer = lib.mkIf cfg.webcam.enable {
      description = "WebRTC camera stream for Mainsail";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/dev/video0";
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.camera-streamer}"
          "--camera-path=/base/soc/i2c0mux/i2c@1/imx708@1a"
          "--camera-type=libcamera"
          "--camera-format=YUYV"
          "--camera-width=2304"
          "--camera-height=1296"
          "--camera-fps=30"
          "--camera-nbufs=2"
          "--camera-snapshot.height=1080"
          "--camera-video.disabled=0"
          "--camera-video.height=720"
          "--camera-video.options=video_bitrate=4000000"
          "--camera-video.options=h264_profile=constrained_baseline"
          "--camera-stream.height=480"
          "--camera-options=AfMode=2"
          "--camera-options=AfRange=2"
          "--webrtc-ice_servers=turns://${turnUser}:${turnCredential}@${turnHost}:443"
          "--webrtc-disable_client_ice=1"
          "--http-listen=127.0.0.1"
          "--http-port=8080"
          "--rtsp-port"
        ];
        DynamicUser = true;
        SupplementaryGroups = [
          "i2c"
          "video"
        ];
        Restart = "always";
        RestartSec = 10;
        Nice = 10;
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
        CPUWeight = 20;
        MemoryMax = "300M";
      };
    };

    services.nginx.virtualHosts.${config.services.mainsail.hostName} = lib.mkIf cfg.webcam.enable {
      locations."/webcam/" = {
        proxyPass = "http://127.0.0.1:8080/";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
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

    systemd.services.panda-can0 = lib.mkIf cfg.can.enable {
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

    systemd.services.klipper = lib.mkIf cfg.can.enable {
      after = [ "panda-can0.service" ];
      requires = [ "panda-can0.service" ];
    };

    system.stateVersion = "25.05";
  };
}
