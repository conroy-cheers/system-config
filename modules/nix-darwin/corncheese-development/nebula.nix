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
  mesh = import ../../common/corncheese-development/nebula-mesh.nix {
    inherit lib hostName;
    inherit (cfg) lighthouseEndpoints;
  };
  ssh = if mesh.host == null then null else mesh.host.ssh;
  sshIdentity = if ssh == null then null else mesh.inventory.identities.${ssh.identity};
  active = cfg.enable && mesh.managedHost && meta.pubkey != null && mesh.hasHostCertificate;
  keyPath = config.age.secrets."corncheese.nebula.key".path;
  hostsBlock = pkgs.writeText "nebula-corncheese-hosts" (
    lib.concatStringsSep "\n" (
      [ "# BEGIN corncheese Nebula hosts" ]
      ++ lib.mapAttrsToList (name: address: "${address} ${name}.nebula") mesh.hostAddresses
      ++ [ "# END corncheese Nebula hosts" ]
    )
    + "\n"
  );
  nebulaConfig = (pkgs.formats.yaml { }).generate "nebula-corncheese.yml" {
    pki = {
      ca = mesh.caCertificate;
      cert = mesh.hostCertificate;
      key = keyPath;
    };
    static_host_map = mesh.staticHostMap;
    static_map.cadence = "30s";
    lighthouse = {
      am_lighthouse = mesh.isLighthouse;
      hosts = mesh.lighthouses;
      interval = 10;
      serve_dns = false;
    };
    relay = {
      am_relay = mesh.isLighthouse;
      inherit (mesh) relays;
      use_relays = true;
    };
    listen = {
      host = "0.0.0.0";
      port = mesh.listenPort;
    };
    # Let macOS allocate a valid utun device instead of using the Linux name.
    tun.disabled = false;
    punchy = {
      punch = true;
      respond = true;
    };
    inherit (mesh) firewall;
  };
in
{
  imports = [ ../../common/corncheese-development/nebula.nix ];

  config = lib.mkMerge [
    (lib.mkIf (ssh != null) {
      assertions = [
        {
          assertion = ssh.user == "root" || lib.elem ssh.user config.users.knownUsers;
          message = ''
            Nebula SSH user `${ssh.user}` for `${hostName}` must already be
            declared in users.knownUsers.
          '';
        }
      ];

      users.users.${ssh.user}.openssh.authorizedKeys.keys = [ sshIdentity.publicKey ];
    })

    {
      system.activationScripts.networking.text = lib.mkAfter ''
        nebula_hosts_tmp=$(/usr/bin/mktemp /etc/hosts.nebula.XXXXXX)
        /usr/bin/awk '
          $0 == "# BEGIN corncheese Nebula hosts" { managed = 1; next }
          $0 == "# END corncheese Nebula hosts" { managed = 0; next }
          !managed { print }
        ' /etc/hosts > "$nebula_hosts_tmp"
        ${lib.optionalString active ''
          /bin/cat ${hostsBlock} >> "$nebula_hosts_tmp"
        ''}
        /usr/sbin/chown root:wheel "$nebula_hosts_tmp"
        /bin/chmod 0644 "$nebula_hosts_tmp"
        /bin/mv "$nebula_hosts_tmp" /etc/hosts
      '';

      launchd.daemons.nebula-corncheese = lib.mkIf active {
        script = ''
          if [ ! -r ${lib.escapeShellArg keyPath} ]; then
            echo "Nebula key is not readable yet: ${keyPath}" >&2
            exit 1
          fi

          exec ${lib.getExe' pkgs.nebula "nebula"} -config ${nebulaConfig}
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 5;
          StandardOutPath = "/var/log/nebula-corncheese.out.log";
          StandardErrorPath = "/var/log/nebula-corncheese.err.log";
        };
      };
    }
  ];
}
