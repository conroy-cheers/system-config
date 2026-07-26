{
  lib,
  hostName,
  lighthouseEndpoints,
}:

let
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
    kiki = "10.42.42.9";
  };

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
