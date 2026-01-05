{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.andromeda.development;
in
{
  config = lib.mkIf cfg.tailscale.enable {
    # make the tailscale command usable to users
    environment.systemPackages = [ pkgs.tailscale ];

    # enable the tailscale service
    services.tailscale.enable = true;
  };
}
