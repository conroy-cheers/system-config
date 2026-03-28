{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  hyprGameSubmapd = pkgs.writeShellApplication {
    name = "hypr-game-submapd";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      hyprland
      jq
      socat
    ];
    text = ''
      set -euo pipefail

      state_file=/tmp/hypr_submap
      mode=""
      instance=""

      find_socket() {
        local runtime_dir
        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        find "$runtime_dir/hypr" -mindepth 2 -maxdepth 2 -path '*/.socket2.sock' -print 2>/dev/null | sort | tail -n 1
      }

      hypr() {
        hyprctl -i "$instance" "$@"
      }

      has_game_tag() {
        hypr -j activewindow 2>/dev/null | jq -e '
          type == "object" and any((.tags // [])[]?; startswith("game"))
        ' >/dev/null 2>&1
      }

      set_mode() {
        local next_mode
        next_mode="$1"

        if [[ "$mode" == "$next_mode" ]]; then
          return
        fi

        if [[ "$next_mode" == "game" ]]; then
          hypr dispatch submap game >/dev/null 2>&1 || true
          printf '%s' game > "$state_file"
        else
          hypr dispatch submap reset >/dev/null 2>&1 || true
          : > "$state_file"
        fi

        mode="$next_mode"
      }

      sync_mode() {
        if has_game_tag; then
          set_mode game
        else
          set_mode ""
        fi
      }

      while true; do
        socket="$(find_socket)"

        if [[ -z "$socket" ]]; then
          instance=""
          set_mode ""
          sleep 1
          continue
        fi

        instance="$(basename "$(dirname "$socket")")"

        sync_mode

        while IFS= read -r event; do
          case "$event" in
            activewindow*|closewindow*|focusedmon*|openwindow*|workspace*)
              sync_mode
              ;;
          esac
        done < <(socat -u UNIX-CONNECT:"$socket" STDOUT 2>/dev/null)

        set_mode ""
        sleep 1
      done
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      (pkgs.writeScriptBin "hyprworkspace" ''
        #!/bin/sh
        # from https://github.com/taylor85345/hyprland-dotfiles/blob/master/hypr/scripts/workspace
        monitors=/tmp/hypr/monitors_temp
        hyprctl monitors > $monitors

        if [[ -z $1 ]]; then
          workspace=$(grep -B 5 "focused: no" "$monitors" | awk 'NR==1 {print $3}')
        else
          workspace=$1
        fi

        activemonitor=$(grep -B 11 "focused: yes" "$monitors" | awk 'NR==1 {print $2}')
        passivemonitor=$(grep  -B 6 "($workspace)" "$monitors" | awk 'NR==1 {print $2}')
        #activews=$(grep -A 2 "$activemonitor" "$monitors" | awk 'NR==3 {print $1}' RS='(' FS=')')
        passivews=$(grep -A 6 "Monitor $passivemonitor" "$monitors" | awk 'NR==4 {print $1}' RS='(' FS=')')

        if [[ $workspace -eq $passivews ]] && [[ $activemonitor != "$passivemonitor" ]]; then
        hyprctl dispatch workspace "$workspace" && hyprctl dispatch swapactiveworkspaces "$activemonitor" "$passivemonitor" && hyprctl dispatch workspace "$workspace"
          echo $activemonitor $passivemonitor
        else
          hyprctl dispatch moveworkspacetomonitor "$workspace $activemonitor" && hyprctl dispatch workspace "$workspace"
        fi

        exit 0
      '')
      # Spotifyd is slow with playerctl, use dbus insted.
      (pkgs.writeScriptBin "hyprmusic" ''
        #!/bin/sh
        set -euo pipefail
        case "''${1:-}" in
          next)
            MEMBER=Next
            ;;

          previous)
            MEMBER=Previous
            ;;

          play)
            MEMBER=Play
            ;;

          pause)
            MEMBER=Pause
            ;;

          play-pause)
            MEMBER=PlayPause
            ;;

          *)
            echo "Usage: $0 next|previous|play|pause|play-pause"
            exit 1
            ;;

        esac

        exec dbus-send                                                \
          --print-reply                                               \
          --dest="org.mpris.MediaPlayer2.spotify_player" \
          /org/mpris/MediaPlayer2                                     \
          "org.mpris.MediaPlayer2.Player.$MEMBER"
      '')
      (pkgs.writeScriptBin "hyprtheme" ''
        #!/bin/sh
        home-manager switch --flake .
        pkill ags
        ags 1>/dev/null 2>&1 &
        disown ags
        hyprctl reload
        pkill -USR2 cava
      '')
      hyprGameSubmapd
    ];

    systemd.user.services.hypr-game-submapd = {
      Unit = {
        Description = "Switch Hyprland into the game submap for tagged windows";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe hyprGameSubmapd;
        Restart = "always";
        RestartSec = 1;
        Type = "simple";
      };
    };
  };
}
