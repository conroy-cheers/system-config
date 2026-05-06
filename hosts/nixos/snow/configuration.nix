{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  beluga = "10.1.1.127";
  sleet = "10.1.0.133";
  webSecure = [ "web-secure" ];
  auth = [ "middlewares-authentik" ];
  mkRouter =
    {
      rule,
      service,
      middlewares ? [ ],
      priority ? null,
      entryPoints ? webSecure,
      tlsOptions ? null,
    }:
    {
      inherit
        entryPoints
        rule
        service
        ;
      tls = {
        certResolver = "default";
      }
      // lib.optionalAttrs (tlsOptions != null) { options = tlsOptions; };
    }
    // lib.optionalAttrs (middlewares != [ ]) { inherit middlewares; }
    // lib.optionalAttrs (priority != null) { inherit priority; };
  mkService = url: {
    loadBalancer = {
      passHostHeader = true;
      servers = [ { inherit url; } ];
      responseForwarding.flushInterval = "100ms";
    };
  };
  mkInsecureService =
    transport: url:
    lib.recursiveUpdate (mkService url) {
      loadBalancer.serversTransport = transport;
    };
in
{
  imports = [
    ./hardware-configuration.nix
    ./network.nix
  ];

  boot = {
    growPartition = true;
    loader.grub.device = "/dev/vda";
  };

  networking.hostName = "snow";
  time.timeZone = "Australia/Melbourne";

  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
    gc = {
      automatic = true;
      dates = "04:30";
    };
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "conroy" ];
    };
  };

  corncheese = {
    development = {
      enable = false;
      githubAccess.enable = false;
      remoteBuilders.enable = false;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
    };
    wm.enable = false;
  };

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "web-secure";
            scheme = "https";
          };
        };
        web-secure = {
          address = ":443";
          transport.respondingTimeouts.readTimeout = "3600s";
          http.tls.certResolver = "default";
        };
        matrix-federation.address = ":8448";
        traefik.address = ":8080";
      };
      certificatesResolvers.default.acme = {
        email = "conroy@corncheese.org";
        storage = "${config.services.traefik.dataDir}/acme.json";
        tlsChallenge = true;
      };
      api = {
        dashboard = true;
        insecure = true;
      };
      log = {
        filePath = "${config.services.traefik.dataDir}/traefik.log";
        format = "json";
        level = "INFO";
      };
      accessLog = {
        filePath = "${config.services.traefik.dataDir}/traefik-access.log";
        format = "json";
      };
    };
    dynamicConfigOptions = {
      http = {
        routers = {
          traefik-rtr = mkRouter {
            rule = "Host(`traefik.corncheese.org`)";
            service = "api@internal";
            middlewares = auth;
          };
          authentik = mkRouter {
            rule = "Host(`authentik.corncheese.org`) || Host(`authentik.conroycheers.me`)";
            service = "authentik";
          };
          authentik-outpost = mkRouter {
            rule = "(HostRegexp(`{subdomain:[a-z0-9-.]+}home.conroycheers.me`) || HostRegexp(`{subdomain:[a-z0-9-.]+}corncheese.org`)) && PathPrefix(`/outpost.goauthentik.io/`)";
            service = "authentik";
            priority = 156;
          };
          authelia = mkRouter {
            rule = "Host(`auth.corncheese.org`)";
            service = "authelia";
          };
          home-assistant = mkRouter {
            rule = "Host(`assistant.home.conroycheers.me`)";
            service = "home-assistant";
            middlewares = auth;
          };
          matrix = mkRouter {
            rule = "Host(`matrix.corncheese.org`) || Host(`sygnal.corncheese.org`) || Host(`dimension.corncheese.org`) || Host(`element.corncheese.org`) || Host(`goneb.corncheese.org`) || Host(`stats.corncheese.org`) || Host(`jitsi.corncheese.org`) || Host(`wsproxy.corncheese.org`)";
            service = "matrix";
            priority = 200;
          };
          matrix-federation = mkRouter {
            rule = "Host(`matrix.corncheese.org`)";
            service = "matrix-federation";
            entryPoints = [ "matrix-federation" ];
            priority = 200;
          };
          matrix-well-known = mkRouter {
            rule = "Host(`corncheese.org`) && PathPrefix(`/.well-known/matrix`)";
            service = "matrix-well-known";
            middlewares = [ "matrix-well-known-host" ];
          };
          pve = mkRouter {
            rule = "Host(`pve.corncheese.org`)";
            service = "pve";
          };
          omada = mkRouter {
            rule = "Host(`omada.home.conroycheers.me`)";
            service = "omada";
          };
          panda = mkRouter {
            rule = "Host(`panda.home.conroycheers.me`)";
            service = "panda";
            middlewares = auth ++ [ "corn-cors" ];
          };
          moonraker = mkRouter {
            rule = "Host(`panda.home.conroycheers.me`) && PathRegexp(`^/(websocket|printer|api|access|machine|server)`)";
            service = "moonraker";
            middlewares = auth ++ [ "corn-cors" ];
            priority = 99;
          };
          atuin = mkRouter {
            rule = "Host(`atuin.corncheese.org`)";
            service = "atuin";
          };
          changedetection = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/changedetection`)";
            service = "changedetection";
            middlewares = auth ++ [
              "strip-changedetection"
              "corn-cors"
            ];
          };
          changedetection-manifest = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/changedetection`) && PathRegexp(`site\\.webmanifest(?:\\?|$)`)";
            service = "changedetection";
            middlewares = [ "strip-changedetection" ];
            priority = 105;
          };
          homepage = mkRouter {
            rule = "Host(`home.conroycheers.me`) && (PathPrefix(`/home`) || PathRegexp(`^/_next/(.+\\.(css|js|woff2))`) || PathRegexp(`^/api/(widgets|ping|docker|services|hash|bookmarks|validate|revalidate|releases)/*`) || Path(`/favicon.ico`) || PathRegexp(`^/favicon-.*\\.png`) || Path(`/homepage.ico`) || PathPrefix(`/images/`))";
            service = "homepage";
            middlewares = auth ++ [
              "strip-homepage"
              "corn-cors"
            ];
            priority = 309;
          };
          homepage-root = mkRouter {
            rule = "Host(`home.conroycheers.me`) && Path(`/`)";
            service = "homepage";
            middlewares = [ "homepage-redirect" ];
            priority = 1000;
          };
          homepage-manifest = mkRouter {
            rule = "Host(`home.conroycheers.me`) && (Path(`/site.webmanifest`) || Path(`/android-chrome-192x192.png`) || Path(`/android-chrome-512x512.png`))";
            service = "homepage";
            priority = 100;
          };
          homepage-config-css = mkRouter {
            rule = "Host(`home.conroycheers.me`) && Path(`/api/config/custom.css`)";
            service = "homepage";
            middlewares = [ "homepage-css-mime-type" ];
          };
          homepage-config-js = mkRouter {
            rule = "Host(`home.conroycheers.me`) && Path(`/api/config/custom.js`)";
            service = "homepage";
            middlewares = [ "homepage-js-mime-type" ];
          };
          icloudpd = mkRouter {
            rule = "Host(`icloudpd.home.conroycheers.me`)";
            service = "icloudpd";
            middlewares = auth;
          };
          librechat = mkRouter {
            rule = "Host(`librechat.corncheese.org`)";
            service = "librechat";
          };
          webfinger = mkRouter {
            rule = "Host(`corncheese.org`) && Path(`/.well-known/webfinger`)";
            service = "webfinger";
          };
          portainer = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/portainer`)";
            service = "portainer";
            middlewares = auth ++ [ "strip-portainer" ];
          };
          flood-music = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/music/flood`)";
            service = "flood-music";
            middlewares = auth;
          };
          flood-media = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/media/flood`)";
            service = "flood-media";
            middlewares = auth;
          };
          sabnzbd = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/media/sabnzbd`)";
            service = "sabnzbd";
            middlewares = auth;
          };
          prowlarr = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/media/prowlarr`)";
            service = "prowlarr";
            middlewares = auth;
          };
          sonarr-tv = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/tv/sonarr`)";
            service = "sonarr-tv";
          };
          sonarr-anime = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/anime/sonarr`)";
            service = "sonarr-anime";
          };
          attic = mkRouter {
            rule = "Host(`cache.corncheese.org`)";
            service = "attic";
            tlsOptions = "nix-cache-http1";
          };
          garage = mkRouter {
            rule = "Host(`garage.corncheese.org`)";
            service = "garage";
            tlsOptions = "nix-cache-http1";
          };
          hydra = mkRouter {
            rule = "Host(`hydra.corncheese.org`)";
            service = "hydra";
          };
          minecraft-web = mkRouter {
            rule = "Host(`lasagne.xyz`)";
            service = "minecraft-web";
          };
          filebrowser-quantum = mkRouter {
            rule = "Host(`home.conroycheers.me`) && PathPrefix(`/files`)";
            service = "filebrowser-quantum";
            middlewares = auth;
          };
        };
        services = {
          authentik = mkService "http://${beluga}:9000";
          authelia = mkService "http://${sleet}:9091";
          home-assistant = mkService "http://${sleet}:8123";
          matrix = mkService "http://matrix.lan:81";
          matrix-federation = mkService "http://matrix.lan:8449";
          matrix-well-known = mkService "http://matrix.lan:81";
          pve = mkInsecureService "pve-transport" "https://10.1.1.3:8006/";
          omada = mkInsecureService "omada-transport" "https://beluga.lan:8043/";
          panda = mkService "http://voron-panda/";
          moonraker = mkService "http://voron-panda:7125";
          atuin = mkService "http://${beluga}:8888";
          changedetection = mkService "http://${beluga}:5000";
          homepage = mkService "http://${beluga}:3010";
          icloudpd = mkService "http://${beluga}:8990";
          librechat = mkService "http://${beluga}:3080";
          webfinger = mkService "http://${beluga}:7158";
          portainer = mkService "http://${beluga}:9009";
          flood-music = mkService "http://${sleet}:3000";
          flood-media = mkService "http://${sleet}:3001";
          sabnzbd = mkService "http://${sleet}:8080";
          prowlarr = mkService "http://${sleet}:9696";
          sonarr-tv = mkService "http://${sleet}:8989";
          sonarr-anime = mkService "http://${sleet}:8990";
          attic = mkService "http://${sleet}:9400";
          garage = mkService "http://${sleet}:3900";
          hydra = mkService "http://${sleet}:3010";
          minecraft-web = mkService "http://${sleet}:7080";
          filebrowser-quantum = mkService "http://${sleet}:8088";
        };
        middlewares = {
          middlewares-authentik.forwardAuth = {
            address = "http://${beluga}:9000/outpost.goauthentik.io/auth/traefik";
            trustForwardHeader = true;
            authResponseHeaders = [
              "X-authentik-username"
              "X-authentik-groups"
              "X-authentik-email"
              "X-authentik-name"
              "X-authentik-uid"
              "X-authentik-jwt"
              "X-authentik-meta-jwks"
              "X-authentik-meta-outpost"
              "X-authentik-meta-provider"
              "X-authentik-meta-app"
              "X-authentik-meta-version"
            ];
          };
          corn-cors.headers = {
            accessControlAllowMethods = [
              "GET"
              "OPTIONS"
              "PUT"
            ];
            accessControlAllowOriginList = [
              "https://authentik.corncheese.org"
              "https://authentik.conroycheers.me"
              "https://home.conroycheers.me"
              "https://panda.home.conroycheers.me"
              "https://omada.home.conroycheers.me"
            ];
            accessControlMaxAge = 100;
            addVaryHeader = true;
          };
          strip-changedetection.stripPrefix.prefixes = [ "/changedetection" ];
          strip-homepage.stripPrefix.prefixes = [ "/home" ];
          strip-portainer.stripPrefix.prefixes = [ "/portainer" ];
          homepage-redirect.redirectRegex = {
            regex = "^https://home\\.conroycheers\\.me/$";
            replacement = "https://home.conroycheers.me/home/";
            permanent = true;
          };
          homepage-css-mime-type.headers.customResponseHeaders.Content-Type = "text/css";
          homepage-js-mime-type.headers.customResponseHeaders.Content-Type = "application/javascript";
          matrix-well-known-host.headers.customRequestHeaders.Host = "matrix.corncheese.org";
        };
        serversTransports = {
          pve-transport.insecureSkipVerify = true;
          omada-transport.insecureSkipVerify = true;
        };
      };
      tls.options.nix-cache-http1.alpnProtocols = [ "http/1.1" ];
    };
  };

  services.mosquitto = {
    enable = true;
    persistence = true;
    dataDir = "/var/lib/mosquitto";
    listeners = [
      {
        port = 1883;
        settings.allow_anonymous = false;
        users.mosquitto = {
          hashedPassword = "$7$101$fVG1AhwRLXPS0i71$CS+AECYd4PVAbVuSSt2WWe0b61ZethYigMDh5MXNV58sJNpZlUvZ9bCgfUEL2qE9GH243Qvd4mL5WywxoyzJ5A==";
          acl = [ "readwrite #" ];
        };
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      80
      443
      1883
      8080
      8448
    ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowTcpForwarding = "yes";
    };
  };

  services.qemuGuest.enable = true;

  users.users.conroy = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKbNTRUenigTtrUSGKImYezWzT/KFOR7dZSpSuvsKNY"
    ];
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
  };

  programs.fish.enable = true;

  security.sudo-rs = {
    enable = true;
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
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    jq
    mosquitto
    vim
  ];

  system.stateVersion = "25.11";
}
