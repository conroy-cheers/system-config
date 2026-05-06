{ ... }:

{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    nameservers = [ "10.1.0.1" ];
    extraHosts = ''
      10.1.1.120 snow.lan infra-traefik.lan
      10.1.0.203 mqtt.lan
    '';
  };

  systemd.network = {
    enable = true;
    networks."10-ens18" = {
      matchConfig.Name = "ens18";
      address = [
        "10.1.1.120/22"
        "10.1.0.203/22"
      ];
      gateway = [ "10.1.0.1" ];
      dns = [ "10.1.0.1" ];
      networkConfig = {
        IPv6AcceptRA = true;
        MulticastDNS = true;
      };
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
