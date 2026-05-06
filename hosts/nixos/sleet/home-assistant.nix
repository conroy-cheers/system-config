{
  config,
  lib,
  pkgs,
  ...
}:

let
  legacyAddress = "10.1.1.114";
  interface = "ens18";
in
{
  services.home-assistant = {
    enable = true;
    openFirewall = true;
    extraComponents = [
      "apple_tv"
      "backup"
      "brother"
      "default_config"
      "esphome"
      "fronius"
      "go2rtc"
      "google_translate"
      "group"
      "homekit"
      "homekit_controller"
      "ipp"
      "met"
      "mobile_app"
      "mqtt"
      "otbr"
      "radio_browser"
      "sun"
      "thread"
      "tplink"
      "workday"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      adaptive_lighting
    ];
    config = {
      default_config = { };

      frontend.themes = "!include_dir_merge_named themes";

      tts = [
        { platform = "google_translate"; }
      ];

      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";

      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "10.1.1.127"
          "10.1.1.120"
          "10.1.0.133"
        ];
      };

      auth_header = {
        username_header = "Remote-User";
        debug = true;
      };

      homekit.filter = {
        include_domains = [
          "light"
          "switch"
        ];
        include_entity_globs = [
          "binary_sensor.*_occupancy"
        ];
      };

      logger = {
        default = "info";
        logs."custom_components.auth_header" = "debug";
      };

      binary_sensor = [
        {
          platform = "template";
          sensors.bedroom_light_to_foyer = {
            friendly_name = "Bedroom Light -> Foyer";
            device_class = "opening";
            value_template = "{{ is_state('binary_sensor.bedroom_door_contact', 'on') and is_state('light.bedroom_uplighter', 'on') }}";
          };
        }
      ];
    };
  };

  # Keep the old HAOS LAN address alive on sleet during and after cutover so
  # homeassistant.lan and integrations that pinned the old IP keep working.
  systemd.services.home-assistant-legacy-address = {
    description = "Assign legacy HAOS address to sleet";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager-wait-online.service" ];
    wants = [ "NetworkManager-wait-online.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe' pkgs.iproute2 "ip"} address replace ${legacyAddress}/22 dev ${interface}";
      ExecStop = "${lib.getExe' pkgs.iproute2 "ip"} address del ${legacyAddress}/22 dev ${interface}";
    };
  };

  systemd.services.home-assistant = {
    wants = [ "home-assistant-legacy-address.service" ];
    after = [ "home-assistant-legacy-address.service" ];
  };
}
