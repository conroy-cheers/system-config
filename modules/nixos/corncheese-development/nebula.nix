{
  config,
  lib,
  meta,
  ...
}:

let
  cfg = config.corncheese.development.nebula;
  hostName = config.networking.hostName;
  mesh = import ../../common/corncheese-development/nebula-mesh.nix {
    inherit lib hostName;
    inherit (cfg) lighthouseEndpoints;
  };
  active = cfg.enable && mesh.managedHost && meta.pubkey != null && mesh.hasHostCertificate;
in
{
  imports = [ ../../common/corncheese-development/nebula.nix ];

  config = lib.mkIf active {
    age.secrets."corncheese.nebula.key" = {
      owner = "nebula-corncheese";
      group = "nebula-corncheese";
    };

    networking.hosts = lib.mapAttrs' (
      name: address: lib.nameValuePair address [ "${name}.nebula" ]
    ) mesh.hostAddresses;

    services.nebula.networks.corncheese = {
      enable = true;
      ca = mesh.caCertificate;
      cert = mesh.hostCertificate;
      key = config.age.secrets."corncheese.nebula.key".path;

      inherit (mesh)
        isLighthouse
        lighthouses
        relays
        staticHostMap
        firewall
        ;
      isRelay = mesh.isLighthouse;
      listen.port = mesh.listenPort;

      settings = {
        static_map.cadence = "30s";
        lighthouse.interval = 10;
        punchy = {
          punch = true;
          respond = true;
        };
      };
    };
  };
}
