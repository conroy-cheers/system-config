{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.networking;
in
{
  options.corncheese.networking.regulatoryDomain = lib.mkOption {
    type = lib.types.strMatching "^[A-Z]{2}$";
    default = "AU";
    description = ''
      ISO 3166-1 alpha-2 regulatory domain supplied to cfg80211 before Wi-Fi
      radios are enumerated.
    '';
  };

  config = lib.mkMerge [
    {
      # Establish the correct channel table before any Wi-Fi radios appear.
      # Learning the country later from an access point can leave an existing
      # wpa_supplicant process with its initial world-domain restrictions.
      boot.extraModprobeConfig = ''
        options cfg80211 ieee80211_regdom=${cfg.regulatoryDomain}
      '';
    }

    (lib.mkIf config.networking.networkmanager.enable {
      # NetworkManager system profiles are normal machine configuration for a
      # local desktop administrator. This also lets non-interactive clients
      # such as Steam create their device-specific profiles without a prompt.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (
            action.id == "org.freedesktop.NetworkManager.settings.modify.system" &&
            subject.local &&
            subject.active &&
            subject.isInGroup("wheel")
          ) {
            return polkit.Result.YES;
          }
        });
      '';
    })

    (lib.mkIf (config.programs.steam.enable && config.networking.networkmanager.enable) {
      # Steam currently writes this WPA3-only 6 GHz network as WPA-PSK.
      # Preserve its generated password while correcting the profile after
      # creation on every Steam-enabled NixOS desktop using NetworkManager.
      systemd.services.steam-frame-network-profile = {
        description = "Correct Steam Frame NetworkManager profile";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        wants = [ "NetworkManager.service" ];
        path = [ pkgs.networkmanager ];
        serviceConfig.Type = "oneshot";
        script = ''
          profile='Steam Frame Wireless Adapter'
          settings="$(${pkgs.networkmanager}/bin/nmcli -g \
            '802-11-wireless-security.key-mgmt,802-11-wireless-security.pmf,802-11-wireless.band,connection.autoconnect' \
            connection show "$profile" 2>/dev/null)" || exit 0

          if [[ "$settings" == $'sae\n3\n6GHz\nno' ]]; then
            exit 0
          fi

          nmcli connection modify "$profile" \
            802-11-wireless-security.key-mgmt sae \
            802-11-wireless-security.pmf required \
            802-11-wireless.band 6GHz \
            connection.autoconnect no
        '';
      };

      systemd.paths.steam-frame-network-profile = {
        description = "Watch for Steam Frame NetworkManager profiles";
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = "/etc/NetworkManager/system-connections";
      };
    })
  ];
}
