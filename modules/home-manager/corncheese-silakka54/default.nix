{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.silakka54;
  silakka54 = lib.getExe pkgs.silakka54;
  soundCfg = cfg.sound;
  soundEngine = lib.getExe pkgs.silakka54-sound;
  soundSend = lib.getExe' pkgs.silakka54-sound "silakka54-sound-send";
  soundDesign = lib.getExe' pkgs.silakka54-sound "silakka54-sound-design";
  soundProtocol = "${pkgs.silakka54}/share/silakka54/midi-protocol.json";

  soundRuntime = pkgs.writeShellApplication {
    name = "silakka54-sound-runtime";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      jq
      pipewire
      procps
      wireplumber
    ];
    text = ''
      set -euo pipefail
      export LD_LIBRARY_PATH=${pkgs.pipewire.jack}/lib

      state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/silakka54-sound"
      state_file="$state_root/state"
      volume_file="$state_root/volume-db"
      default_volume=${lib.escapeShellArg (toString soundCfg.volumeDb)}

      desired_state() {
        if [[ -f "$state_file" ]]; then cat "$state_file"; else printf 'on\n'; fi
      }
      volume_db() {
        if [[ -f "$volume_file" ]]; then cat "$volume_file"; else printf '%s\n' "$default_volume"; fi
      }
      midi_source() {
        pw-link -o 2>/dev/null | awk 'tolower($0) ~ /silakka54/ && tolower($0) !~ /silakka54_sound/ { print; exit }'
      }
      default_sink() {
        pw-metadata -n default 0 2>/dev/null \
          | grep "key:'default.audio.sink'" \
          | tail -n 1 \
          | sed -n 's/.*"name":"\([^"]*\)".*/\1/p'
      }
      target_prefix() {
        local sink
        sink="$(default_sink || true)"
        if [[ "$sink" == alsa_output.usb-MOTU_M2_* || "$sink" == effect_input.eq ]] \
          && pw-link -i 2>/dev/null | grep -Fxq 'effect_input.eq:playback_FL'; then
          sink=effect_input.eq
        fi
        printf '%s\n' "$sink"
      }
      disconnect_other_outputs() {
        local output="$1" wanted="$2" existing
        while IFS= read -r existing; do
          [[ "$existing" == "$wanted" ]] || pw-link -d "$output" "$existing" 2>/dev/null || true
        done < <(pw-link -ol 2>/dev/null | awk -v port="$output" '
          $0 == port { found=1; next }
          found && /^  \|-> / { sub(/^  \|-> /, ""); print; next }
          found { exit }
        ')
      }
      disconnect_other_inputs() {
        local input="$1" wanted="$2" existing
        while IFS= read -r existing; do
          [[ "$existing" == "$wanted" ]] || pw-link -d "$existing" "$input" 2>/dev/null || true
        done < <(pw-link -il 2>/dev/null | awk -v port="$input" '
          $0 == port { found=1; next }
          found && /^  \|<- / { sub(/^  \|<- /, ""); print; next }
          found { exit }
        ')
      }
      connect_graph() {
        local source target
        source="$(midi_source || true)"
        target="$(target_prefix || true)"
        disconnect_other_inputs 'silakka54_sound:midi_in' "$source"
        disconnect_other_outputs 'silakka54_sound:out_left' "''${target:+$target:playback_FL}"
        disconnect_other_outputs 'silakka54_sound:out_right' "''${target:+$target:playback_FR}"
        [[ -n "$source" ]] && pw-link "$source" 'silakka54_sound:midi_in' 2>/dev/null || true
        [[ -n "$target" ]] && pw-link 'silakka54_sound:out_left' "$target:playback_FL" 2>/dev/null || true
        [[ -n "$target" ]] && pw-link 'silakka54_sound:out_right' "$target:playback_FR" 2>/dev/null || true
      }
      apply_volume() {
        local node_id db linear
        node_id="$(pw-dump 2>/dev/null | jq -r '
          map(select(.type == "PipeWire:Interface:Node"))
          | map(select(.info.props."node.name" == "silakka54_sound"))
          | first | .id // empty
        ')"
        [[ -n "$node_id" ]] || return 0
        db="$(volume_db)"
        linear="$(awk -v db="$db" 'BEGIN { printf "%.8f", exp(db * log(10) / 20) }')"
        wpctl set-volume "$node_id" "$linear" >/dev/null 2>&1 || true
      }
      stop_child() {
        if [[ -n "''${child_pid:-}" ]] && kill -0 "$child_pid" 2>/dev/null; then
          kill "$child_pid" 2>/dev/null || true
          wait "$child_pid" 2>/dev/null || true
        fi
      }
      terminate() {
        stop_child
        exit 0
      }
      trap stop_child EXIT
      trap terminate INT TERM

      jq -e '
        .protocol == "silakka54-semantic-midi"
        and .version == 1 and .channel == 16
        and ([.candidate_controls[].control] == [20,21,22,23,24,25])
        and ([.modifier_controls[].control] == [30,31,32,33])
        and .layer_message == "program-change"
        and (.layers == [
          {"program":0,"name":"Base"},
          {"program":1,"name":"Num"},
          {"program":2,"name":"Nav"},
          {"program":3,"name":"Sym"},
          {"program":4,"name":"Game"}
        ])
      ' ${soundProtocol} >/dev/null

      while true; do
        if [[ "$(desired_state)" != on ]] || [[ -z "$(midi_source || true)" ]]; then
          sleep 1
          continue
        fi

        ${soundEngine} &
        child_pid=$!
        for _ in $(seq 1 50); do
          if pw-link -i 2>/dev/null | grep -Fxq 'silakka54_sound:midi_in'; then break; fi
          kill -0 "$child_pid" 2>/dev/null || wait "$child_pid"
          sleep 0.1
        done
        connect_graph
        apply_volume

        while kill -0 "$child_pid" 2>/dev/null \
          && [[ "$(desired_state)" == on ]] \
          && [[ -n "$(midi_source || true)" ]]; do
          connect_graph
          apply_volume
          sleep 1
        done
        stop_child
        child_pid=""
      done
    '';
  };

  soundControl = pkgs.writeShellApplication {
    name = "silakka54-sound";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      jq
      pipewire
      systemd
      wireplumber
    ];
    text = ''
      set -euo pipefail
      export LD_LIBRARY_PATH=${pkgs.pipewire.jack}/lib
      state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/silakka54-sound"
      state_file="$state_root/state"
      volume_file="$state_root/volume-db"
      default_volume=${lib.escapeShellArg (toString soundCfg.volumeDb)}
      requested_frames=${toString soundCfg.latencyFrames}

      desired_state() { if [[ -f "$state_file" ]]; then cat "$state_file"; else printf 'on\n'; fi; }
      volume_db() { if [[ -f "$volume_file" ]]; then cat "$volume_file"; else printf '%s\n' "$default_volume"; fi; }
      write_state() { mkdir -p "$state_root"; printf '%s\n' "$1" > "$state_file"; }
      restart_service() { systemctl --user restart silakka54-sound.service; }
      default_sink() {
        pw-metadata -n default 0 2>/dev/null | grep "key:'default.audio.sink'" | tail -n 1 \
          | sed -n 's/.*"name":"\([^"]*\)".*/\1/p'
      }
      target_prefix() {
        local sink
        sink="$(default_sink || true)"
        if [[ "$sink" == alsa_output.usb-MOTU_M2_* || "$sink" == effect_input.eq ]] \
          && pw-link -i 2>/dev/null | grep -Fxq 'effect_input.eq:playback_FL'; then
          sink=effect_input.eq
        fi
        printf '%s\n' "$sink"
      }
      actual_quantum() {
        pw-metadata -n settings 0 2>/dev/null | sed -n "s/.*key:'clock.quantum' value:'\([^']*\)'.*/\1/p" | tail -n 1
      }
      input_linked() {
        local input="$1" source="$2"
        [[ -n "$source" ]] || return 1
        pw-link -il 2>/dev/null | awk -v port="$input" -v source="$source" '
          $0 == port { found=1; next }
          found && $0 == "  |<- " source { linked=1 }
          found && $0 !~ /^  \|<- / { exit }
          END { exit !linked }
        '
      }
      output_linked() {
        local output="$1" target="$2"
        [[ -n "$target" ]] || return 1
        pw-link -ol 2>/dev/null | awk -v port="$output" -v target="$target" '
          $0 == port { found=1; next }
          found && $0 == "  |-> " target { linked=1 }
          found && $0 !~ /^  \|-> / { exit }
          END { exit !linked }
        '
      }
      usage() { printf 'Usage: silakka54-sound on|off|toggle|status|volume [DB]|test|design\n'; }

      command="''${1:-status}"
      case "$command" in
        on) write_state on; restart_service ;;
        off) write_state off; restart_service ;;
        toggle)
          if [[ "$(desired_state)" == on ]]; then write_state off; else write_state on; fi
          restart_service
          ;;
        volume)
          if [[ $# -eq 1 ]]; then volume_db; exit; fi
          if [[ $# -ne 2 ]] || [[ ! "$2" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; then
            echo 'volume requires one numeric dB value' >&2
            exit 2
          fi
          db="$2"
          awk -v db="$db" 'BEGIN { if (db < -60 || db > 0) exit 1 }' \
            || { echo 'volume must be between -60 and 0 dB' >&2; exit 2; }
          mkdir -p "$state_root"
          printf '%s\n' "$db" > "$volume_file"
          restart_service
          ;;
        status)
          desired="$(desired_state)"
          live="$(systemctl --user is-active silakka54-sound.service 2>/dev/null || true)"
          node_id="$(pw-dump 2>/dev/null | jq -r '
            map(select(.type == "PipeWire:Interface:Node"))
            | map(select(.info.props."node.name" == "silakka54_sound"))
            | first | .id // empty
          ')"
          midi="$(pw-link -o 2>/dev/null | awk 'tolower($0) ~ /silakka54/ && tolower($0) !~ /silakka54_sound/ { print; exit }')"
          target="$(target_prefix || true)"
          if input_linked 'silakka54_sound:midi_in' "$midi"; then midi_link=connected; else midi_link=disconnected; fi
          if output_linked 'silakka54_sound:out_left' "''${target:+$target:playback_FL}" \
            && output_linked 'silakka54_sound:out_right' "''${target:+$target:playback_FR}"; then
            audio_link=connected
          else
            audio_link=disconnected
          fi
          quantum="$(actual_quantum || true)"
          printf 'desired=%s service=%s engine=%s midi=%s midi_link=%s target=%s audio_link=%s volume_db=%s requested_quantum=%s actual_quantum=%s\n' \
            "$desired" "$live" "''${node_id:-unavailable}" "''${midi:-unavailable}" "$midi_link" \
            "''${target:-unavailable}" "$audio_link" "$(volume_db)" "$requested_frames" "''${quantum:-unknown}"
          if [[ "$quantum" =~ ^[0-9]+$ ]] && (( quantum > requested_frames )); then
            printf 'warning: PipeWire graph quantum %s exceeds the requested %s frames\n' "$quantum" "$requested_frames" >&2
          fi
          ;;
        test)
          pw-link -i | grep -Fxq 'silakka54_sound:midi_in' || { echo 'sound engine is not running' >&2; exit 1; }
          for control in 20 21 22 23 24 25; do ${soundSend} cc "$control" 127; sleep 0.04; ${soundSend} cc "$control" 0; done
          for control in 30 31 32; do ${soundSend} cc "$control" 127; sleep 0.18; ${soundSend} cc "$control" 0; done
          for controls in '30 31' '30 32' '31 32' '30 31 32'; do
            read -r -a chord <<< "$controls"
            for control in "''${chord[@]}"; do ${soundSend} cc "$control" 127; done
            sleep 0.18
            for control in "''${chord[@]}"; do ${soundSend} cc "$control" 0; done
          done
          ${soundSend} cc 33 127; sleep 0.15; ${soundSend} cc 33 0
          for program in 1 2 3 4 0; do ${soundSend} layer "$program"; sleep 0.18; done
          ;;
        design)
          systemctl --user stop silakka54-sound.service
          design_home="$(mktemp -d --tmpdir="''${XDG_RUNTIME_DIR:-/tmp}" silakka54-sound-design.XXXXXX)"
          restore() {
            if [[ -n "''${design_pid:-}" ]] && kill -0 "$design_pid" 2>/dev/null; then
              kill "$design_pid" 2>/dev/null || true
            fi
            rm -rf -- "$design_home"
            systemctl --user start silakka54-sound.service
          }
          trap restore EXIT INT TERM
          HOME="$design_home" PIPEWIRE_LATENCY="$requested_frames/48000" ${soundDesign} &
          design_pid=$!
          for _ in $(seq 1 50); do
            pw-link -o 2>/dev/null | grep -Fxq 'silakka54-sound-design:out_0' && break
            kill -0 "$design_pid" 2>/dev/null || wait "$design_pid"
            sleep 0.1
          done
          target="$(target_prefix)"
          pw-link 'silakka54-sound-design:out_0' "$target:playback_FL"
          pw-link 'silakka54-sound-design:out_1' "$target:playback_FR"
          wait "$design_pid"
          ;;
        -h|--help|help) usage ;;
        *) usage >&2; exit 2 ;;
      esac
    '';
  };
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "corncheese" "wm" "silakka54" "enable" ]
      [ "corncheese" "silakka54" "enable" ]
    )
  ];

  options.corncheese.silakka54 = {
    enable = lib.mkEnableOption "Silakka54 firmware and keymap synchronization";
    overlayLayers = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.listOf (
          lib.types.enum (
            map (layer: layer.name)
              (builtins.fromJSON (builtins.readFile ../../../packages/silakka54/configuration.json)).via.layers
          )
        )
      );
      default = [
        "Num"
        "Nav"
        "Sym"
      ];
      example = [
        "Num"
        "Sym"
      ];
      description = ''
        Silakka54 layer names for which the keyboard layer viewer is shown.
        By default the overlay is shown for Num, Nav, and Sym, but not Base.
        Set this to null to show every layer. An empty list disables the
        overlay for Silakka54 without disabling synchronization.
      '';
    };
    sound = {
      enable = lib.mkEnableOption "low-latency modifier and layer sounds";
      latencyFrames = lib.mkOption {
        type = lib.types.enum [
          64
          128
          256
        ];
        default = 128;
        description = "Requested PipeWire/JACK quantum at 48 kHz; this does not force the graph.";
      };
      volumeDb = lib.mkOption {
        type = lib.types.numbers.between (-60) 0;
        default = -24;
        description = "Default sound stream volume in dB before any persistent runtime override.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          pkgs.silakka54
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.keymap-editor
          pkgs.libnotify
        ];
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        systemd.user.services.silakka54-watch = {
          Unit = {
            Description = "Watch and reconcile Silakka54 VIA state";
            After = [ "default.target" ];
          };
          Service = {
            ExecStart = "${silakka54} watch";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "default.target" ];
        };

        home.packages = lib.mkIf soundCfg.enable [
          pkgs.silakka54-sound
          soundControl
        ];

        systemd.user.services.silakka54-sound = lib.mkIf soundCfg.enable {
          Unit = {
            Description = "Silakka54 modifier and layer sound supervisor";
            After = [
              "graphical-session.target"
              "pipewire.service"
              "wireplumber.service"
            ];
            Wants = [
              "pipewire.service"
              "wireplumber.service"
            ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe soundRuntime;
            Environment = [
              "LD_LIBRARY_PATH=${pkgs.pipewire.jack}/lib"
              "PIPEWIRE_LATENCY=${toString soundCfg.latencyFrames}/48000"
            ];
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.silakka54-sync = {
          enable = true;
          config = {
            ProgramArguments = [
              silakka54
              "watch"
            ];
            ProcessType = "Background";
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
          };
        };
      })
    ]
  );
}
