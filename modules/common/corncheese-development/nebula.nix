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
  mesh = import ./nebula-mesh.nix {
    inherit lib hostName;
    inherit (cfg) lighthouseEndpoints;
  };
  hasHostIdentity = meta.pubkey != null;
  keyProvisioned = cfg.enable && mesh.managedHost && hasHostIdentity;
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
      default = mesh.hostAddresses.${hostName} or null;
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
        lib.optional (cfg.enable && !mesh.managedHost) ''
          Nebula is enabled, but ${hostName} has no address in the corncheese mesh.
        ''
        ++ lib.optional (cfg.enable && mesh.managedHost && !hasHostIdentity) ''
          Nebula is enabled for ${hostName}, but this image-only host has no age rekey recipient;
          the service is withheld rather than placing its private key in the Nix store.
        ''
        ++ lib.optional (keyProvisioned && !mesh.hasHostCertificate) ''
          Nebula key material is provisioned for ${hostName}, but its signed certificate is missing;
          the service is withheld until nebula-pki/${hostName}.crt is added.
        '';
    }

    (lib.mkIf keyProvisioned {
      age.secrets."corncheese.nebula.key" = {
        rekeyFile = lib.repoSecret "corncheese/nebula/${hostName}.key.age";
        owner = lib.mkDefault "0";
        group = lib.mkDefault "0";
        mode = "0400";
      };

      environment.systemPackages = [ pkgs.nebula ];
    })
  ];
}
