{ ... }:

{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    nameservers = [
      "10.1.1.2"
      "10.1.1.12"
    ];
  };

  systemd.network = {
    enable = true;
    networks."10-ens18" = {
      matchConfig.Name = "ens18";
      address = [ "10.1.1.121/22" ];
      gateway = [ "10.1.0.1" ];
      dns = [
        "10.1.1.2"
        "10.1.1.12"
      ];
      domains = [
        "~lan"
        "~home.conroycheers.me"
        "~corncheese.org"
      ];
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
