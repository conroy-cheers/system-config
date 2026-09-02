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
  pandaTurnPort = 3478;
  pandaTurnUser = "panda-webrtc";
  pandaTurnCredential = "vnrGVsjHTMEsJlmYvoLXCUeq";
  wotboxStateMigration = pkgs.writeShellScript "wotbox-state-subvolume" ''
    set -eu
    state_path=/var/lib/wotbox
    rollback_path=/var/lib/.wotbox-pre-subvolume

    if ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$state_path" >/dev/null 2>&1; then
      exit 0
    fi
    if [ -e "$rollback_path" ]; then
      echo "Refusing Wotbox state migration because $rollback_path already exists" >&2
      exit 1
    fi
    if [ -e "$state_path" ]; then
      ${pkgs.coreutils}/bin/mv "$state_path" "$rollback_path"
    else
      ${pkgs.coreutils}/bin/mkdir -p "$rollback_path"
    fi
    ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$state_path"
    ${pkgs.coreutils}/bin/cp -a --reflink=always "$rollback_path"/. "$state_path"/
    ${pkgs.coreutils}/bin/chown -R wotbox:wotbox "$state_path"
    ${pkgs.coreutils}/bin/chmod 0700 "$state_path"
    ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$state_path" >/dev/null
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.impermanence.nixosModules.impermanence
    ./impermanence.nix
    ./network.nix
    ./home-assistant.nix
    ../corncheese-public-services.nix
    inputs.corncheese-server.nixosModules.corncheese-server
    inputs.wotbox.nixosModules.default
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
        "wasm32-wasip1"
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
  age.secrets."wotbox.ops-token" = {
    rekeyFile = lib.repoSecret "wotbox/ops-token.age";
    owner = "wotbox";
    mode = "0400";
  };
  age.secrets."wotbox.red-token" = {
    rekeyFile = lib.repoSecret "wotbox/red-token.age";
    owner = "wotbox";
    mode = "0400";
  };
  age.secrets."wotbox.qbittorrent-api-key" = {
    rekeyFile = lib.repoSecret "wotbox/qbittorrent-api-key.age";
    owner = "wotbox";
    mode = "0400";
  };
  age.secrets."wotbox.lastfm-api-key" = {
    rekeyFile = lib.repoSecret "wotbox/lastfm-api-key.age";
    owner = "wotbox";
    mode = "0400";
  };
  age.secrets."wotbox.plex-token" = {
    rekeyFile = lib.repoSecret "wotbox/plex-token.age";
    owner = "wotbox";
    mode = "0400";
  };
  age.secrets."corncheese.mail.icloud" = {
    rekeyFile = lib.repoSecret "corncheese/mail/icloud.age";
    owner = "root";
    mode = "0400";
  };

  corncheese-server = {
    topology = {
      hosts = {
        sleet.address = "10.1.0.133";
        snow.address = "10.1.1.120";
      };
      ingress.hosts = [
        "snow"
      ];
    };
    ingress.enable = true;
    _meta.services.panda-turn.endpoint = {
      scheme = "tcp";
      port = pandaTurnPort;
    };
    _meta.ingress.routes = {
      panda.backend.url = lib.mkForce "http://panda.lan";
      moonraker.backend.url = lib.mkForce "http://panda.lan";
    };
    auth.authelia = {
      enable = true;
    };
    media = {
      enable = true;
      filebrowserQuantum.enable = true;
      torrent.music.apiKeyFile = config.age.secrets."wotbox.qbittorrent-api-key".path;
    };
    matrix = {
      enable = true;
      bridges.enable = true;
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

  services.wotbox = {
    enable = true;
    listenAddress = config.corncheese-server._meta.topology.serviceListenAddress "wotbox" "127.0.0.1";
    basePath = "/media/music/wotbox";
    lastfmApiKeyFile = config.age.secrets."wotbox.lastfm-api-key".path;
    plex = {
      tokenFile = config.age.secrets."wotbox.plex-token".path;
      sectionId = 4;
      libraryRoots = [
        "/mnt/media/Downloads/torrent/complete/ops"
        "/mnt/media/Downloads/torrent/complete/red"
      ];
    };
    trackers.ops = {
      kind = "ops";
      baseUrl = "https://orpheus.network";
      tokenFile = config.age.secrets."wotbox.ops-token".path;
    };
    trackers.red = {
      kind = "red";
      baseUrl = "https://redacted.sh";
      tokenFile = config.age.secrets."wotbox.red-token".path;
      announceHosts = [ "flacsfor.me" ];
    };
    downloadClients.music = {
      baseUrl = "http://127.0.0.1:8001";
      apiKeyFile = config.age.secrets."wotbox.qbittorrent-api-key".path;
    };
    downloadProfiles.ops = {
      client = "music";
      savePath = "/mnt/media/Downloads/torrent/complete/ops";
      tag = "ops";
    };
    downloadProfiles.red = {
      client = "music";
      savePath = "/mnt/media/Downloads/torrent/complete/red";
      tag = "red";
    };
  };

  # Keep Wotbox's database and immutable Library closure in one snapshot unit.
  # The migration preserves the original directory as a reflinked rollback copy
  # and is deliberately non-destructive on subsequent activations.
  # ExecStartPre runs only after systemd has stopped the previous Wotbox
  # process, so the one-time directory-to-subvolume migration is offline.
  systemd.services.wotbox.serviceConfig.ExecStartPre = [ "+${wotboxStateMigration}" ];

  services.btrbk.instances.wotbox = {
    onCalendar = "hourly";
    snapshotOnly = true;
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "48h";
      snapshot_preserve = "14d 8w 6m";
      volume."/var/lib" = {
        snapshot_dir = ".wotbox-snapshots";
        subvolume.wotbox = { };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/.wotbox-snapshots 0700 root root - -"
  ];

  services.icloud-mail-mcp = {
    enable = true;
    passwordFile = config.age.secrets."corncheese.mail.icloud".path;
    smtp = {
      enable = true;
      attachments = {
        enable = true;
        allowedAzureBlobAccountPrefixes = [ "oaisdmntpr" ];
      };
    };
    aliases = [
      "conroy@corncheese.org"
      "conroy@conroycheers.me"
    ];
    listenAddress = config.corncheese-server._meta.topology.serviceListenAddress "icloud-mail-mcp" "127.0.0.1";
    port = 8781;
    publicUrl = "https://mail.corncheese.org";
    oauth = {
      issuer = "https://auth.corncheese.org";
      jwksUri = "https://auth.corncheese.org/jwks.json";
      audience = "https://mail.corncheese.org/mcp";
      requiredScopes = [
        "mail.read"
        "mail.send"
      ];
      supportedScopes = [
        "mail.read"
        "mail.send"
      ];
    };
  };

  corncheese-server.auth.authelia.notifier.smtp = {
    enable = true;
    username = "conroy.cheers@icloud.com";
    passwordFile = config.age.secrets."corncheese.mail.icloud".path;
    sender = "Authelia <conroy.cheers@icloud.com>";
    startupCheckAddress = "conroy@corncheese.org";
  };

  services.bunnings-powerpass-invoices = {
    enable = true;
    automaticRenewal.enable = true;
    listenAddress = config.corncheese-server._meta.topology.serviceListenAddress "bunnings-powerpass-invoices" "127.0.0.1";
    port = 8782;
    publicUrl = "https://powerpass.corncheese.org";
    oauth = {
      issuer = "https://auth.corncheese.org";
      jwksUri = "https://auth.corncheese.org/jwks.json";
      audience = "https://powerpass.corncheese.org/mcp";
      requiredScopes = [ "powerpass.invoices.read" ];
    };
  };

  services.authelia.instances.main.settings.identity_providers.oidc.lifespans.custom.chatgpt-mcp.refresh_token =
    "180d";

  services.hydra.extraConfig = ''
    evaluator_max_memory_size = 32768
  '';

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
    listening-port = pandaTurnPort;
    listening-ips = [ (config.corncheese-server._meta.topology.hostAddress "sleet") ];
    relay-ips = [ (config.corncheese-server._meta.topology.hostAddress "sleet") ];
    "lt-cred-mech" = true;
    "no-cli" = true;
    "no-tls" = true;
    "no-dtls" = true;
    extraConfig = ''
      user=${pandaTurnUser}:${pandaTurnCredential}
      fingerprint
      total-quota=20
    '';
  };

  systemd.services.ultramoji = {
    description = "Ultramoji 4D web app";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${ultramojiPackage}/bin/ultramoji-server --bind ${config.corncheese-server._meta.topology.serviceListenAddress "ultramoji" "127.0.0.1"} --port ${toString ultramojiPort}";
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
  fonts.fontconfig.enable = lib.mkForce false;

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
