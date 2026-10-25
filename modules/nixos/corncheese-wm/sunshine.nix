{
  config,
  lib,
  ...
}:

let
  cfg = config.corncheese.wm.sunshine;
  port = config.services.sunshine.settings.port;

  nebulaRules =
    proto: offsets:
    lib.concatMap (
      host:
      map (offset: {
        inherit host proto;
        port = toString (port + offset);
      }) offsets
    ) cfg.nebula.allowedHosts;
in
{
  options.corncheese.wm.sunshine = {
    enable = lib.mkEnableOption "Sunshine desktop streaming for Moonlight";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "conroy" ];
      description = ''
        Existing local users running Sunshine who need uinput access for
        remote keyboard, mouse, and controller input.
      '';
    };

    nebula = {
      network = lib.mkOption {
        type = lib.types.str;
        default = "corncheese";
        description = "Existing Nebula network to add Moonlight firewall rules to.";
      };

      allowedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "kombu" ];
        description = ''
          Nebula certificate host names allowed to connect to Sunshine.
          An empty list leaves Nebula unchanged. Configure the listening
          address separately with services.sunshine.settings.bind_address.
        '';
      };
    };
  };

  config = lib.mkIf (config.corncheese.wm.enable && cfg.enable) {
    assertions = lib.optional (cfg.nebula.allowedHosts != [ ]) {
      assertion = config.services.nebula.networks.${cfg.nebula.network}.enable or false;
      message = "corncheese.wm.sunshine.nebula.allowedHosts requires an enabled Nebula network `${cfg.nebula.network}`.";
    };

    services.sunshine = {
      enable = true;
      autoStart = lib.mkDefault true;
      settings = {
        sunshine_name = lib.mkDefault config.networking.hostName;
        # The tray's synchronous D-Bus calls can stall the pairing handshake.
        system_tray = lib.mkDefault "disabled";
        upnp = lib.mkDefault "disabled";
        # Automatic output selection also permits a compositor's fallback output.
        output_name = lib.mkDefault "";
      };
      applications.apps = lib.mkDefault [
        {
          name = "Desktop";
          image-path = "desktop.png";
        }
      ];
    };

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ "uinput" ];
    });

    services.nebula.networks = lib.optionalAttrs (cfg.nebula.allowedHosts != [ ]) {
      ${cfg.nebula.network}.firewall.inbound =
        nebulaRules "tcp" [
          (-5)
          0
          1
          21
        ]
        ++ nebulaRules "udp" [
          9
          10
          11
          13
          21
        ];
    };
  };
}
