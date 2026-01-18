{
  lib,
  pkgs,
  ...
}:
let
  fan2go' = pkgs.fan2go.override { enableNVML = pkgs.config.cudaSupport; };

  getClcData = pkgs.writeShellScript "get-clc-data" ''
    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <key> <multiplier>"
        echo "Example: $0 'Liquid temperature' 1"
        exit 1
    fi

    key="$1"
    multiplier="$2"

    ${lib.getExe pkgs.liquidctl} --match EVGA status --json \
      | ${lib.getExe pkgs.jq} -r --arg k "$key" --argjson m "$multiplier" '
        .[0].status[]
        | select(.key==$k)
        | (.value * $m | floor)
    '
  '';

  getClcFanRpm = pkgs.writeShellScript "get-clc-fan-rpm" ''
    # cursed sleep so fan2go doesn't try to read fan RPM and liquid temp simultaneously
    sleep 0.1
    ${getClcData} "Fan speed" 1
  '';

  getClcLiquidTemp = pkgs.writeShellScript "get-clc-liquid-temp" ''
    ${getClcData} "Liquid temperature" "1000"
  '';

  clcFanSpeed = pkgs.writeShellScript "clc-fan-speed" ''
    STATE_FILE="/run/clc-fan-speed"
    DEFAULT_SPEED=15

    get_last_speed() {
        if [[ -f "$STATE_FILE" ]]; then
            cat "$STATE_FILE"
        else
            echo "$DEFAULT_SPEED"
        fi
    }

    if [[ $# -eq 0 ]]; then
        get_last_speed
        exit 0
    fi

    SPEED="$1"
    if ! [[ "$SPEED" =~ ^[0-9]+$ ]] || ((SPEED < 0 || SPEED > 100)); then
        echo "Error: fan speed must be in range 0-100" >&2
        exit 1
    fi

    ${lib.getExe pkgs.liquidctl} --match EVGA set fan speed "$SPEED"
    echo "$SPEED" > "$STATE_FILE"
  '';
in
{
  environment.systemPackages = with pkgs; [
    fan2go'
    liquidctl
  ];

  systemd.services.liquidcfg = {
    description = "AIO startup service";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = ''
        ${lib.getExe pkgs.liquidctl} initialize all
      '';
      Type = "oneshot";
    };
  };

  services.fan2go = {
    enable = true;
    package = fan2go';
    settings = {
      fans = [
        {
          id = "exhaust_top";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 2;
          };
          curve = "exhaust_top_curve";
        }
        {
          id = "intake_bottom";
          hwmon = {
            platform = "it8613-isa-*";
            rpmChannel = 3;
          };
          curve = "intake_bottom_curve";
        }
        {
          id = "clc_intake_side";
          cmd = {
            setPwm = {
              exec = "${clcFanSpeed}";
              args = [ "%pwm%" ];
            };
            getPwm = {
              exec = "${clcFanSpeed}";
            };
            getRpm = {
              exec = "${getClcFanRpm}";
            };
          };
          curve = "clc_curve";
        }
      ];
      sensors = [
        {
          id = "gpu_temp";
          hwmon = {
            platform = "amdgpu-*-*";
            index = 1;
          };
        }
        {
          id = "cpu_package_temp";
          hwmon = {
            platform = "k10temp-pci-*";
            index = 1;
          };
        }
        {
          id = "cpu_liquid_temp";
          cmd = {
            exec = "${getClcLiquidTemp}";
          };
        }
      ];
      curves = [
        {
          id = "clc_curve";
          linear = {
            sensor = "cpu_liquid_temp";
            steps = [
              { "30" = 5; }
              { "40" = 50; }
              { "65" = 255; }
            ];
          };
        }
        {
          id = "intake_bottom_curve";
          linear = {
            sensor = "gpu_temp";
            steps = [
              { "30" = 0; }
              { "40" = 50; }
              { "80" = 200; }
            ];
          };
        }
        {
          id = "exhaust_top_curve";
          function = {
            type = "sum";
            curves = [
              "clc_curve"
              "intake_bottom_curve"
            ];
          };
        }
      ];
    };
  };
}
