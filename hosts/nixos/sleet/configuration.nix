# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

let
  ultramojiPackage = inputs.ultramoji-4d.packages.${pkgs.stdenv.hostPlatform.system}.ultramoji-server;
  ultramojiPort = 8765;
  vllmPackage = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.vllm-p100;
  vllmModel = "cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit";
  vllmServedModelName = "gemma4-26b";
  vllmPort = 8000;
  vllmLlGuidancePath = "${pkgs.python3Packages.llguidance}/${pkgs.python3.sitePackages}";
  openWebuiPort = 8180;
  pandaTurnHost = "turn.home.conroycheers.me";
  pandaTurnPort = 3478;
  pandaTurnUser = "panda-webrtc";
  pandaTurnCredential = "vnrGVsjHTMEsJlmYvoLXCUeq";
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.impermanence.nixosModules.impermanence
    ./impermanence.nix
    ./network.nix
    inputs.corncheese-server.nixosModules.corncheese-server
  ];

  ### Set boot options
  boot = {
    # Use the systemd-boot boot loader.
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Enable running aarch64 binaries using qemu
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "wasm32-wasi"
        "x86_64-windows"
      ];
    };

    supportedFilesystems = [ "btrfs" ];
  };

  networking.hostName = "sleet"; # Define your hostname.
  ### Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  ### Set your time zone.
  time.timeZone = "Australia/Melbourne";

  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    config.credential.helper = "libsecret";
  };

  corncheese = {
    development = {
      enable = true;
      githubAccess.enable = true;
      remoteBuilders.enable = false;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm.enable = false;
  };

  programs.ccache = {
    enable = true;
    cacheDir = "/nix/var/cache/ccache";
  };
  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  age.secrets."corncheese.nix-cache.env" = {
    rekeyFile = lib.repoSecret "corncheese/nix-cache/env.age";
  };
  age.secrets."hydra-admin-password" = {
    rekeyFile = lib.repoSecret "hydra/admin-password.age";
    owner = "root";
    mode = "0400";
  };
  age.secrets."corncheese.github.hydra-token" = {
    rekeyFile = lib.repoSecret "corncheese/github/hydra-token.age";
    owner = "root";
    mode = "0400";
  };

  corncheese-server = {
    ingress.enable = true;
    _meta.ingress.routes = {
      panda.backend.url = lib.mkForce "http://panda.lan";
      moonraker.backend.url = lib.mkForce "http://panda.lan";
      ultramoji = {
        host = "ultramoji.corncheese.org";
        auth.mode = "public";
        backend.url = "http://127.0.0.1:${toString ultramojiPort}";
      };
      vllm = {
        host = "vllm.corncheese.org";
        auth.mode = "forwardAuth";
        backend.url = "http://127.0.0.1:${toString vllmPort}";
      };
      openwebui = {
        host = "openwebui.corncheese.org";
        auth.mode = "forwardAuth";
        backend.url = "http://127.0.0.1:${toString openWebuiPort}";
      };
    };
    auth.authelia = {
      enable = true;
    };
    media = {
      enable = true;
      filebrowserQuantum.enable = true;
    };
    games = {
      minecraft.enable = true;
    };
    hydra = {
      enable = true;
      admin.passwordFile = config.age.secrets."hydra-admin-password".path;
      github.tokenFile = config.age.secrets."corncheese.github.hydra-token".path;
    };
    nixCache = {
      enable = true;
      environmentFile = config.age.secrets."corncheese.nix-cache.env".path;
    };
  };

  services.authelia.instances.main.settings.session = {
    # Mainsail holds a long-lived Moonraker websocket. Authelia does not see
    # websocket frames as session activity, so a short idle timeout makes
    # reconnects fail with an auth redirect the browser cannot follow.
    inactivity = lib.mkForce "12h";
    expiration = lib.mkForce "24h";
    # Safari does not reliably include a Lax session cookie on WebSocket
    # handshakes. The Moonraker websocket is same-host with Mainsail, but it is
    # not a top-level navigation, so use an explicit cross-request cookie.
    same_site = lib.mkForce "none";
  };

  services.coturn = {
    enable = true;
    realm = "home.conroycheers.me";
    listening-port = pandaTurnPort;
    listening-ips = [ "127.0.0.1" ];
    relay-ips = [ "10.1.0.133" ];
    "lt-cred-mech" = true;
    "no-cli" = true;
    "no-udp" = true;
    "no-tls" = true;
    "no-dtls" = true;
    extraConfig = ''
      user=${pandaTurnUser}:${pandaTurnCredential}
      fingerprint
      total-quota=20
    '';
  };

  services.traefik.dynamicConfigOptions.tcp = {
    routers.panda-turn = {
      entryPoints = [ "web-secure" ];
      rule = "HostSNI(`${pandaTurnHost}`)";
      service = "panda-turn";
      tls.certResolver = "default";
    };
    services.panda-turn.loadBalancer.servers = [
      { address = "127.0.0.1:${toString pandaTurnPort}"; }
    ];
  };

  systemd.services.ultramoji = {
    description = "Ultramoji 4D web app";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${ultramojiPackage}/bin/ultramoji-server --bind 127.0.0.1 --port ${toString ultramojiPort}";
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      SystemCallArchitectures = "native";
    };
  };

  age-template.files."hydra-github-authorizations.conf".mode = lib.mkForce "0440";

  # log conroy into atuin sync
  age.secrets."corncheese.atuin.key" = {
    rekeyFile = lib.repoSecret "corncheese/atuin/key.age";
    owner = "conroy";
    mode = "0400";
  };
  home-manager.users.conroy = {
    corncheese = {
      shell.atuin = {
        key = config.age.secrets."corncheese.atuin.key".path;
      };
    };
  };

  ### Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  ### Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  nix = {
    gc = {
      automatic = true;
      dates = "04:00";
    };
    settings = {
      trusted-users = [ "conroy" ];
    };
  };

  # nopasswd for sudo
  security.sudo-rs = {
    enable = true; # !config.security.sudo.enable;
    inherit (config.security.sudo) extraRules;
  };
  security.sudo = {
    enable = false;
    extraRules = [
      {
        users = [ "conroy" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ]; # "SETENV" # Adding the following could be a good idea
          }
        ];
      }
    ];
  };

  ### Fonts
  fonts.fontconfig.enable = false;

  hardware.graphics.enable = true;
  hardware.nvidia = {
    # Tesla P100 is Pascal, so use the proprietary kernel module.
    open = false;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  services.plex.accelerationDevices = [ "*" ];
  users.users.plex.extraGroups = [
    "render"
    "video"
  ];

  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = openWebuiPort;
    environment = {
      ENABLE_OLLAMA_API = "False";
      ENABLE_LOGIN_FORM = "False";
      ENABLE_PASSWORD_CHANGE_FORM = "False";
      ENABLE_PERSISTENT_CONFIG = "False";
      WEBUI_URL = "https://openwebui.corncheese.org";
      CORS_ALLOW_ORIGIN = "https://openwebui.corncheese.org";
      OPENAI_API_BASE_URL = "http://127.0.0.1:${toString vllmPort}/v1";
      OPENAI_API_KEY = "local-vllm";
      DEFAULT_MODELS = vllmServedModelName;
      WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "Remote-Email";
      WEBUI_AUTH_TRUSTED_NAME_HEADER = "Remote-Name";
      WEBUI_AUTH_TRUSTED_GROUPS_HEADER = "Remote-Groups";
    };
  };

  users.groups.vllm = { };
  users.users.vllm = {
    isSystemUser = true;
    group = "vllm";
    extraGroups = [
      "render"
      "video"
    ];
  };

  systemd.services.vllm-gemma4 = {
    description = "vLLM Gemma4 26B API server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "nvidia-persistenced.service"
    ];
    wants = [ "network-online.target" ];

    environment = {
      CUDA_VISIBLE_DEVICES = "0,1";
      HF_HOME = "/var/lib/vllm/huggingface";
      HOME = "/var/lib/vllm";
      PYTHONPATH = vllmLlGuidancePath;
      VLLM_MOE_USE_DEEP_GEMM = "0";
      VLLM_USE_DEEP_GEMM = "0";
    };
    path = [ pkgs.cudaPackages.cuda_nvcc ];

    serviceConfig = {
      User = "vllm";
      Group = "vllm";
      StateDirectory = "vllm";
      WorkingDirectory = "/var/lib/vllm";
      EnvironmentFile = "-/var/lib/vllm/huggingface/token.env";
      ExecStart = lib.escapeShellArgs [
        "${vllmPackage}/bin/vllm"
        "serve"
        vllmModel
        "--served-model-name"
        vllmServedModelName
        "--host"
        "127.0.0.1"
        "--port"
        (toString vllmPort)
        "--tensor-parallel-size"
        "2"
        "--distributed-executor-backend"
        "mp"
        "--attention-backend"
        "TRITON_ATTN"
        "--dtype"
        "float16"
        "--max-model-len"
        "4096"
        "--max-num-batched-tokens"
        "4096"
        "--gpu-memory-utilization"
        "0.88"
        "--enable-auto-tool-choice"
        "--tool-call-parser"
        "gemma4"
        "--reasoning-parser"
        "gemma4"
        "--chat-template"
        "${inputs.vllm-src}/examples/tool_chat_template_gemma4.jinja"
        "--limit-mm-per-prompt"
        ''{"image": 0, "audio": 0, "video": 0}''
      ];
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
  # environment.sessionVariables = {
  #   # "_JAVA_AWT_WM_NONREPARENTING" = "1";
  #   "XDG_SESSION_TYPE" = "wayland";
  #   # "WLR_NO_HARDWARE_CURSORS" = "1";
  #   "MOZ_DISABLE_RDD_SANDBOX" = "1";
  #   "MOZ_ENABLE_WAYLAND" = "1";
  #   "EGL_PLATFORM" = "wayland";
  #   # "XDG_CURRENT_DESKTOP" = "sway"; # river
  #   "XKB_DEFAULT_LAYOUT" = "us";
  #   "XKB_DEFAULT_VARIANT" = ",phonetic";
  #   "XKB_DEFAULT_OPTIONS" = "caps:escape,grp:lalt_lshift_toggle";
  #   # "WLR_RENDERER" = "vulkan"; # BUG: river crashes
  # };

  # services.displayManager = {
  #   # defaultSession = "river";
  #   sessionPackages = with pkgs; [
  #     hyprland
  #   ];
  # };

  ### Wayland specific
  services.xserver = {
    enable = false; # disable xserver
    videoDrivers = [ "nvidia" ];
  };

  # services.displayManager = {
  #   sddm = {
  #     enable = true;
  #     wayland.enable = true;
  #   };
  # };

  ## X11 specific
  # services.xserver = {
  #   xkb.layout = "us";
  #   xkb.variant = ",phonetic";
  #   xkb.options = "grp:lalt_lshift_toggle";
  # };

  # services.greetd = {
  #   enable = true;
  #   settings = rec {
  #     initial_session = "${pkgs.hyprland}/bin/hyprland";
  #     user = "conroy";
  #   };
  # };

  ### Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      # Forbid root login through SSH.
      PermitRootLogin = "no";
      # Use keys only. Remove if you want to SSH using password (not recommended)
      PasswordAuthentication = false;
    };
  };

  ### Enable CUPS to print documents.
  services.printing.enable = true;

  services.dbus = {
    enable = true;
    packages = [ pkgs.dconf ];
  };

  age.secrets."conroy.user.password" = {
    rekeyFile = lib.repoSecret "home/conroy/user/password.age";
    mode = "440";
  };
  users.users.conroy = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets."conroy.user.password".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKbNTRUenigTtrUSGKImYezWzT/KFOR7dZSpSuvsKNY" # conroy-home
    ];
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
    ];
  };

  programs.fish = {
    enable = true;
  };

  boot.initrd.systemd.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    xdg-utils
    wget
  ];

  # Open ports in the firewall.
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
