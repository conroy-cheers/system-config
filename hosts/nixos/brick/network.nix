{
  ...
}:
{
  environment.systemPackages = [ ];

  networking.extraHosts = ''
    127.0.0.1 brick.local
  '';

  networking.useNetworkd = false;

  networking.networkmanager.enable = true;

  # enable mDNS
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
