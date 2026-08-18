{
  config,
  lib,
  ...
}:
{
  environment.systemPackages = [ ];

  networking.extraHosts = ''
    127.0.0.1 brick.local
  '';

  networking.useNetworkd = false;

  networking.networkmanager.enable = true;
  services.resolved.enable = true;

  age.secrets."corncheese.protonvpn.wireguard" = {
    rekeyFile = lib.repoSecret "corncheese/protonvpn/wireguard.conf.age";
  };

  networking.wg-quick.interfaces.protonvpn = {
    configFile = config.age.secrets."corncheese.protonvpn.wireguard".path;
    autostart = false;
  };

  # enable mDNS
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
