{
  lib,
  hostName,
}:

let
  inventory = import ./nebula-inventory.nix { inherit lib; };
  inherit (inventory) hosts;
  hostAddresses = lib.mapAttrs (_: host: host.address) hosts;
  pkiDir = ./nebula-pki;
  host = hosts.${hostName} or null;
  ownAddress = if host == null then null else host.address;
  lighthouseHosts = lib.filterAttrs (_: candidate: candidate.lighthouse != null) hosts;
  lighthouseAddresses = lib.mapAttrsToList (_: candidate: candidate.address) lighthouseHosts;
  lighthouseEndpointMap = lib.mapAttrs' (
    _: candidate: lib.nameValuePair candidate.address candidate.lighthouse.endpoints
  ) lighthouseHosts;
  isLighthouse = host != null && host.lighthouse != null;
  otherLighthouseAddresses = builtins.filter (address: address != ownAddress) lighthouseAddresses;
  # Nebula is the base mesh: it must never depend on Tailscale for transport.
  # Tailscale can discover Nebula endpoints, so allowing the reverse dependency
  # creates an encapsulation loop. Filter addresses rather than interface names
  # so this also covers peers and platforms with different tunnel device names.
  underlayAddressAllowList = {
    "100.64.0.0/10" = false;
    "fd7a:115c:a1e0::/48" = false;
  };
in
{
  inherit
    hosts
    hostAddresses
    inventory
    lighthouseAddresses
    isLighthouse
    ;

  caCertificate = pkiDir + "/ca.crt";
  hostCertificate = pkiDir + "/${hostName}.crt";
  inherit host;
  managedHost = builtins.hasAttr hostName hosts;
  hasHostCertificate = builtins.pathExists (pkiDir + "/${hostName}.crt");
  lighthouses = otherLighthouseAddresses;
  relays = otherLighthouseAddresses;
  staticHostMap = builtins.removeAttrs lighthouseEndpointMap (
    lib.optional (ownAddress != null) ownAddress
  );
  listenPort = if isLighthouse then 4242 else 0;
  lighthouseAddressFilters = {
    local_allow_list = underlayAddressAllowList;
    remote_allow_list = underlayAddressAllowList;
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
}
