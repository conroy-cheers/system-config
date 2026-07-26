{
  lib,
  hostName,
  lighthouseEndpoints,
}:

let
  hostAddresses = import ./nebula-hosts.nix;
  pkiDir = ./nebula-pki;
  lighthouseAddress = hostAddresses.snow;
  isLighthouse = hostName == "snow";
in
{
  inherit hostAddresses lighthouseAddress isLighthouse;

  caCertificate = pkiDir + "/ca.crt";
  hostCertificate = pkiDir + "/${hostName}.crt";
  managedHost = builtins.hasAttr hostName hostAddresses;
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
