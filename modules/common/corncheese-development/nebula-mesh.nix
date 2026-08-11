{
  lib,
  hostName,
  lighthouseEndpoints,
}:

let
  inventory = import ./nebula-inventory.nix { inherit lib; };
  inherit (inventory) hosts;
  hostAddresses = lib.mapAttrs (_: host: host.address) hosts;
  pkiDir = ./nebula-pki;
  lighthouseAddress = hostAddresses.snow;
  isLighthouse = hostName == "snow";
in
{
  inherit
    hosts
    hostAddresses
    inventory
    lighthouseAddress
    isLighthouse
    ;

  caCertificate = pkiDir + "/ca.crt";
  hostCertificate = pkiDir + "/${hostName}.crt";
  host = hosts.${hostName} or null;
  managedHost = builtins.hasAttr hostName hosts;
  hasHostCertificate = builtins.pathExists (pkiDir + "/${hostName}.crt");
  lighthouses = lib.optional (!isLighthouse) lighthouseAddress;
  relays = lib.optional (!isLighthouse) lighthouseAddress;
  staticHostMap = lib.optionalAttrs (!isLighthouse) {
    ${lighthouseAddress} = lighthouseEndpoints;
  };
  listenPort = if isLighthouse then 4242 else 0;
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
}
