{
  lib,
  inputs,
  pkgs,
  config,
  ...
}:

let
  cfg = config.andromeda.development;
in
{
  config = lib.mkIf cfg.tailscale.enable {
    age.secrets."andromeda.tailscale.env" = {
      rekeyFile = lib.repoSecret "andromeda/tailscale/key.age";
    };

    # make the tailscale command usable to users
    environment.systemPackages = [ pkgs.tailscale ];

    # enable the tailscale service
    services.tailscale.enable = true;

    # NetworkManager-wait-online fails and prevents deployment
    # https://github.com/NixOS/nixpkgs/issues/180175
    systemd.services.NetworkManager-wait-online.enable = false;

    # create a oneshot job to authenticate to Tailscale
    systemd.services.tailscale-autoconnect = {
      description = "Automatic connection to Tailscale";

      # make sure tailscale is running before trying to connect to tailscale
      after = [
        "network-pre.target"
        "tailscale.service"
      ];
      wants = [
        "network-pre.target"
        "tailscale.service"
      ];
      wantedBy = [ "multi-user.target" ];

      # set this service as a oneshot job
      serviceConfig.Type = "oneshot";

      # have the job run this shell script
      script = with pkgs; ''
        # wait for tailscaled to settle
        sleep 2

        # check if we are already authenticated to tailscale
        status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
        if [ $status = "Running" ]; then # if so, then do nothing
          exit 0
        fi

        # otherwise authenticate with tailscale
        ${tailscale}/bin/tailscale up -authkey $(cat ${config.age.secrets."andromeda.tailscale.env".path})
      '';
    };
  };
}
