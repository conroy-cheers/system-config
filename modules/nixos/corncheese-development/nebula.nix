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
  ssh = if mesh.host == null then null else mesh.host.ssh;
  sshIdentity = if ssh == null then null else mesh.inventory.identities.${ssh.identity};
  active = cfg.enable && mesh.managedHost && meta.pubkey != null && mesh.hasHostCertificate;
in
{
  imports = [ ../../common/corncheese-development/nebula.nix ];

  config = lib.mkMerge [
    (lib.mkIf (ssh != null) {
      assertions = [
        {
          assertion =
            ssh.user == "root"
            || config.users.users.${ssh.user}.isNormalUser
            || config.users.users.${ssh.user}.isSystemUser;
          message = ''
            Nebula SSH user `${ssh.user}` for `${hostName}` must already be
            declared as root, a normal user, or a system user.
          '';
        }
      ];

      users.users.${ssh.user}.openssh.authorizedKeys.keys = [ sshIdentity.publicKey ];
    })

    (lib.mkIf active {
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
        tun.device = "nebula.ccheese";

        settings = {
          static_map.cadence = "30s";
          lighthouse.interval = 10;
          punchy = {
            punch = true;
            respond = true;
          };
        };
      };
    })
  ];
}
