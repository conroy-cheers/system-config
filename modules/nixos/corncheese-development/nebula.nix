{
  config,
  lib,
  meta,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.development.nebula;
  hostName = config.networking.hostName;

  # Keep these stable: they are embedded in the signed host certificates.
  hostAddresses = {
    snow = "10.42.42.1";
    sleet = "10.42.42.2";
    brick = "10.42.42.3";
    kombu = "10.42.42.4";
    labtop = "10.42.42.5";
    panda = "10.42.42.6";
    shrimpus = "10.42.42.7";
    wsl-brick = "10.42.42.8";
  };

  lighthouseAddress = hostAddresses.snow;
  isLighthouse = hostName == "snow";
  hasHostIdentity = meta.pubkey != null;
  managedHost = builtins.hasAttr hostName hostAddresses;
  active = cfg.enable && managedHost && hasHostIdentity;
in
{
  options.corncheese.development.nebula = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable the corncheese Nebula mesh";
    };

    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = hostAddresses.${hostName} or null;
      readOnly = true;
      description = "This host's stable address on the corncheese Nebula mesh";
    };

    lighthouseEndpoints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.1.1.120:4242"
        "home.conroycheers.me:4242"
      ];
      description = "LAN and public UDP endpoints for the snow lighthouse";
    };
  };

  config = lib.mkMerge [
    {
      warnings =
        lib.optional (cfg.enable && !managedHost) ''
          Nebula is enabled, but ${hostName} has no address in the corncheese mesh.
        ''
        ++ lib.optional (cfg.enable && managedHost && !hasHostIdentity) ''
          Nebula is enabled for ${hostName}, but this image-only host has no age rekey recipient;
          the service is withheld rather than placing its private key in the Nix store.
        '';
    }

    (lib.mkIf active {
      age.secrets."corncheese.nebula.key" = {
        rekeyFile = lib.repoSecret "corncheese/nebula/${hostName}.key.age";
        owner = "nebula-corncheese";
        group = "nebula-corncheese";
        mode = "0400";
      };

      environment.systemPackages = [ pkgs.nebula ];

      networking.hosts = lib.mapAttrs' (
        name: address: lib.nameValuePair address [ "${name}.nebula" ]
      ) hostAddresses;

      services.nebula.networks.corncheese = {
        enable = true;
        ca = ./nebula-pki/ca.crt;
        cert = ./nebula-pki + "/${hostName}.crt";
        key = config.age.secrets."corncheese.nebula.key".path;

        inherit isLighthouse;
        lighthouses = lib.optional (!isLighthouse) lighthouseAddress;
        isRelay = isLighthouse;
        relays = lib.optional (!isLighthouse) lighthouseAddress;
        staticHostMap = lib.optionalAttrs (!isLighthouse) {
          ${lighthouseAddress} = cfg.lighthouseEndpoints;
        };

        listen.port = if isLighthouse then 4242 else 0;

        settings = {
          static_map.cadence = "30s";
          lighthouse.interval = 10;
          punchy = {
            punch = true;
            respond = true;
          };
        };

        firewall = {
          outbound = [
            {
              port = "any";
              proto = "any";
              host = "any";
            }
          ];
          inbound = [
            {
              port = "any";
              proto = "icmp";
              host = "any";
            }
            {
              port = 22;
              proto = "tcp";
              host = "any";
            }
          ];
        };
      };
    })
  ];
}
