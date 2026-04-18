{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.corncheese.wm.audio;

  motuEq = pkgs.writeShellApplication {
    name = "motu-eq";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
      pipewire
      gnused
    ];
    text = ''
      set -euo pipefail

      state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/motu-eq"
      state_file="$state_root/state"
      default_enabled="${if cfg.equalizer.defaultEnabled then "on" else "off"}"
      wait_for_node=false

      usage() {
        cat <<'EOF'
      Usage: motu-eq on|off|toggle|status|apply [--wait]
      EOF
      }

      desired_state() {
        if [[ -f "$state_file" ]]; then
          cat "$state_file"
        else
          printf '%s\n' "$default_enabled"
        fi
      }

      write_state() {
        mkdir -p "$state_root"
        printf '%s\n' "$1" > "$state_file"
      }

      eq_node_id() {
        pw-dump | jq -r '
          map(select(.type == "PipeWire:Interface:Node"))
          | map(select(.info.props."node.name" == "effect_input.eq"))
          | first
          | .id // empty
        '
      }

      eq_live_disabled() {
        local node_id="$1"
        local line=""
        line="$(pw-metadata -n filters "$node_id" filter.smart.disabled 2>/dev/null | grep "filter.smart.disabled" | tail -n 1 || true)"

        if [[ -z "$line" ]]; then
          printf 'false\n'
          return 0
        fi

        if [[ "$line" =~ value:\'true\' ]]; then
          printf 'true\n'
        else
          printf 'false\n'
        fi
      }

      target_sink_name() {
        local sink=""
        sink="$(
          pw-link -iol \
            | grep -o 'alsa_output\.usb-MOTU_M2_[^:]*\.HiFi__Line__sink' \
            | head -n 1 \
            || true
        )"

        if [[ -n "$sink" ]]; then
          printf '%s\n' "$sink"
          return 0
        fi

        echo "motu-eq: unable to locate MOTU M2 hardware sink" >&2
        return 1
      }

      set_default_sink() {
        local sink_name="$1"
        local json="{\"name\":\"$sink_name\"}"

        pw-metadata -n default 0 default.audio.sink "$json" Spa:String:JSON >/dev/null
        pw-metadata -n default 0 default.configured.audio.sink "$json" Spa:String:JSON >/dev/null
      }

      current_state() {
        local node_id=""
        local disabled=false

        node_id="$(eq_node_id)"
        if [[ -n "$node_id" ]]; then
          disabled="$(eq_live_disabled "$node_id")"
          if [[ "$disabled" == "true" ]]; then
            printf 'off\n'
          else
            printf 'on\n'
          fi
          return 0
        fi

        desired_state
      }

      wait_for_state() {
        local expected="$1"
        local node_id="$2"
        local expected_disabled=false

        if [[ "$expected" == "off" ]]; then
          expected_disabled=true
        fi

        for _ in $(seq 1 50); do
          if [[ "$(eq_live_disabled "$node_id")" == "$expected_disabled" ]]; then
            return 0
          fi
          sleep 0.1
        done

        echo "motu-eq: timed out waiting for live state '$expected'" >&2
        return 1
      }

      wait_for_eq_node() {
        local node_id=""
        for _ in $(seq 1 100); do
          node_id="$(eq_node_id)"
          if [[ -n "$node_id" ]]; then
            printf '%s\n' "$node_id"
            return 0
          fi
          sleep 0.1
        done
        return 1
      }

      apply_state() {
        local state="$1"
        local node_id=""
        local disabled=false

        if [[ "$wait_for_node" == true ]]; then
          node_id="$(wait_for_eq_node || true)"
        else
          node_id="$(eq_node_id)"
        fi

        if [[ -z "$node_id" ]]; then
          echo "motu-eq: effect_input.eq is unavailable" >&2
          return 1
        fi

        set_default_sink "$(target_sink_name)"

        if [[ "$state" == "off" ]]; then
          disabled=true
        fi

        pw-metadata -n filters "$node_id" filter.smart.disabled "$disabled" Spa:String:JSON >/dev/null
        wait_for_state "$state" "$node_id"
      }

      cmd="''${1:-}"
      shift || true

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --wait)
            wait_for_node=true
            ;;
          *)
            echo "motu-eq: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
        esac
        shift
      done

      case "$cmd" in
        on)
          write_state on
          apply_state on
          ;;
        off)
          write_state off
          apply_state off
          ;;
        toggle)
          case "$(current_state)" in
            on) next=off ;;
            off) next=on ;;
            *)
              echo "motu-eq: unable to determine current state" >&2
              exit 1
              ;;
          esac
          write_state "$next"
          apply_state "$next"
          ;;
        apply)
          apply_state "$(desired_state)"
          ;;
        status)
          desired="$(desired_state)"
          node_id="$(eq_node_id)"
          if [[ -n "$node_id" ]]; then
            disabled="$(eq_live_disabled "$node_id")"
            if [[ "$disabled" == "true" ]]; then
              live=off
            else
              live=on
            fi
            printf 'desired=%s live=%s node=%s\n' "$desired" "$live" "$node_id"
          else
            printf 'desired=%s live=unavailable node=\n' "$desired"
          fi
          ;;
        ""|-h|--help|help)
          usage
          ;;
        *)
          echo "motu-eq: unknown command: $cmd" >&2
          usage >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;

    environment.systemPackages = lib.mkIf cfg.equalizer.enable [ motuEq ];

    services.pipewire = lib.mkMerge [
      {
        enable = true;
        alsa = {
          enable = true;
          support32Bit = true;
        };
        pulse = {
          enable = true;
        };
        jack = {
          enable = true;
        };
        extraConfig = {
          pipewire."92-low-latency" = {
            "context.properties" = {
              "default.clock.rate" = 48000;
              "default.clock.quantum" = 256;
              "default.clock.min-quantum" = 32;
              "default.clock.max-quantum" = 4096;
            };
          };
        };
      }
      (lib.mkIf cfg.equalizer.enable {
        extraConfig.pipewire."93-motu-autoeq" = {
          "context.modules" = [
            {
              name = "libpipewire-module-loopback";
              args = {
                "audio.channels" = 2;
                "audio.position" = [
                  "FL"
                  "FR"
                ];
                "node.description" = "MOTU M2";
                "capture.props" = {
                  "node.name" = "effect_input.base";
                  "node.description" = "MOTU M2";
                  "media.name" = "MOTU M2";
                  "media.class" = "Audio/Sink";
                  "filter.smart" = true;
                  "filter.smart.name" = "motu-base";
                  "filter.smart.before" = [ "motu-eq" ];
                  "filter.smart.target" = {
                    "alsa.card_name" = "M2";
                    "device.profile.name" = "HiFi: Line: sink";
                    "media.class" = "Audio/Sink";
                  };
                };
                "playback.props" = {
                  "node.name" = "effect_output.base";
                  "node.description" = "MOTU M2";
                  "node.passive" = true;
                  "stream.dont-remix" = true;
                };
              };
            }
            {
              name = "libpipewire-module-parametric-equalizer";
              args = {
                "equalizer.filepath" = ./HIFIMAN-Ananda-Stealth-ParametricEq.txt;
                "equalizer.description" = "MOTU M2 EQ";
                "audio.channels" = 2;
                "audio.position" = [
                  "FL"
                  "FR"
                ];
                "capture.props" = {
                  "node.name" = "effect_input.eq";
                  "node.description" = "MOTU M2 EQ";
                  "media.name" = "MOTU M2 EQ";
                  "media.class" = "Audio/Sink";
                  "filter.smart" = true;
                  "filter.smart.name" = "motu-eq";
                  "filter.smart.target" = {
                    "alsa.card_name" = "M2";
                    "device.profile.name" = "HiFi: Line: sink";
                    "media.class" = "Audio/Sink";
                  };
                };
                "playback.props" = {
                  "node.name" = "effect_output.eq";
                  "node.description" = "MOTU M2 EQ";
                  "node.passive" = true;
                  "stream.dont-remix" = true;
                };
              };
            }
          ];
        };
      })
    ];

    systemd.user.services = lib.mkIf cfg.equalizer.enable {
      motu-eq-restore = {
        description = "Restore MOTU EQ runtime state";
        wantedBy = [ "graphical-session.target" ];
        after = [
          "graphical-session.target"
          "pipewire.service"
          "wireplumber.service"
        ];
        wants = [
          "pipewire.service"
          "wireplumber.service"
        ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe motuEq} apply --wait";
        };
      };
    };
  };
}
