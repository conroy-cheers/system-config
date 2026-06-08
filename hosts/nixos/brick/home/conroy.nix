{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:

let
  luaString = builtins.toJSON;
  silakka54FirmwarePrompt = pkgs.writeShellScript "silakka54-firmware-prompt" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.silakka54
        pkgs.zenity
        pkgs.coreutils
        pkgs.systemd
      ]
    }:$PATH
    exec silakka54-sync prompt-firmware
  '';
  silakka54LayerViewer = lib.getExe' pkgs.silakka54 "silakka54-layer-viewer";
  silakka54LayerViewerControl = pkgs.writeShellScript "silakka54-layer-viewer-control" ''
    set -eu

    command="''${1:?usage: silakka54-layer-viewer-control <activity|hide|place MONITOR LEFT_MARGIN>}"
    socket="''${XDG_RUNTIME_DIR:?}/silakka54-layer-viewer.sock"

    case "$command" in
      activity)
        ${lib.getExe' pkgs.systemd "systemctl"} --user start silakka54-layer-viewer.service
        tries=0
        while [ ! -S "$socket" ] && [ "$tries" -lt 40 ]; do
          tries=$((tries + 1))
          ${lib.getExe' pkgs.coreutils "sleep"} 0.05
        done
        ;;
      hide)
        ;;
      place)
        monitor="''${2:?usage: silakka54-layer-viewer-control place MONITOR LEFT_MARGIN}"
        left_margin="''${3:?usage: silakka54-layer-viewer-control place MONITOR LEFT_MARGIN}"
        ;;
      *)
        echo "unsupported silakka54-layer-viewer command: $command" >&2
        exit 64
        ;;
    esac

    if [ ! -S "$socket" ]; then
      exit 0
    fi

    case "$command" in
      place)
        exec ${silakka54LayerViewer} --place "$monitor" "$left_margin"
        ;;
      *)
        exec ${silakka54LayerViewer} "--$command"
        ;;
    esac
  '';
  silakka54LayerViewerPlace = pkgs.writeShellApplication {
    name = "silakka54-layer-viewer-place";
    runtimeInputs = with pkgs; [
      coreutils
      hyprland
      jq
    ];
    text = ''
      set -euo pipefail

      if [[ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        exit 0
      fi

      monitors="$(hyprctl monitors -j 2>/dev/null || true)"
      clients="$(hyprctl clients -j 2>/dev/null || true)"
      active="$(hyprctl activewindow -j 2>/dev/null || printf '{}')"
      gaps_in="$(hyprctl getoption general:gaps_in -j 2>/dev/null || printf '{}')"

      if [[ -z "$active" ]]; then
        active="{}"
      fi

      if [[ -z "$monitors" || -z "$clients" ]]; then
        exit 0
      fi

      placement="$(
        jq -n -r \
          --argjson monitors "$monitors" \
          --argjson clients "$clients" \
          --argjson active "$active" \
          --argjson gaps_in "$gaps_in" \
          --argjson overlay_width 659 \
          --argjson overlay_height 284 \
          --argjson bottom_margin 12 \
          '
          def abs: if . < 0 then -. else . end;
          def min($a; $b): if $a < $b then $a else $b end;
          def max($a; $b): if $a > $b then $a else $b end;
          def clamp($value; $lo; $hi):
            if $value < $lo then $lo elif $value > $hi then $hi else $value end;
          def on_monitor($monitor_id; $monitor_name):
            ((.monitor // null) == $monitor_id) or ((.monitor // "") == $monitor_name);
          def on_workspace($workspace_id):
            (.workspace.id // null) == $workspace_id;
          def mapped_visible:
            ((.mapped // true) == true) and ((.hidden // false) | not);
          def configured_gap_margin:
            (((($gaps_in.css // "") | split(" ")[0] | tonumber?) // 0) * 0.7 | ceil);
          def place_near_window($monitor_x; $monitor_width; $band_top; $band_bottom; $gap_margin):
            (.at[0] // 0) as $window_x
            | (.at[1] // 0) as $window_y
            | (.size[0] // 0) as $window_width
            | (.size[1] // 0) as $window_height
            | $monitor_x as $min_x
            | ($monitor_x + $monitor_width - $overlay_width) as $max_x
            | ($window_x + ($window_width / 2) - ($overlay_width / 2)) as $centered_x
            | (($window_y + $window_height) > $band_top and $window_y < $band_bottom) as $overlaps_band
            | if ($max_x < $min_x) then
                $min_x
              elif ($overlaps_band | not) then
                clamp($centered_x; $min_x; $max_x)
              else
                [
                  ($window_x - $gap_margin - $overlay_width),
                  ($window_x + $window_width + $gap_margin)
                ]
                | map(select(. >= $min_x and . <= $max_x) | { left: ., distance: ((. + ($overlay_width / 2) - ($window_x + ($window_width / 2))) | abs) })
                | min_by(.distance).left // clamp($centered_x; $min_x; $max_x)
              end;

          ($monitors | map(select(.focused == true))[0] // $monitors[0] // null) as $monitor
          | if $monitor == null then empty else
              ($monitor.name // "") as $monitor_name
              | ($monitor.id // null) as $monitor_id
              | ($monitor.x // 0) as $monitor_x
              | ($monitor.y // 0) as $monitor_y
              | (if (($monitor.scale // 1) == 0) then 1 else ($monitor.scale // 1) end) as $monitor_scale
              | (($monitor.width // 0) / $monitor_scale) as $monitor_width
              | (($monitor.height // 0) / $monitor_scale) as $monitor_height
              | (if
                  ($active | type == "object")
                  and ($active | mapped_visible)
                  and ($active | on_monitor($monitor_id; $monitor_name))
                then
                  ($active.workspace.id // $monitor.activeWorkspace.id // null)
                else
                  ($monitor.activeWorkspace.id // null)
                end) as $workspace_id
              | ($active.address // "") as $focused_address
              | ($monitor_x + ($monitor_width / 2)) as $monitor_center
              | ($monitor_y + $monitor_height - $overlay_height - $bottom_margin) as $band_top
              | ($monitor_y + $monitor_height) as $band_bottom
              | configured_gap_margin as $gap_margin
              | ($monitor_x + (if $monitor_width > $overlay_width then (($monitor_width - $overlay_width) / 2) else 0 end)) as $fallback_x
              | (if
                  ($active | type == "object")
                  and ($active | mapped_visible)
                  and ($active | on_monitor($monitor_id; $monitor_name))
                  and ($active | on_workspace($workspace_id))
                then
                  { left: ($active | place_near_window($monitor_x; $monitor_width; $band_top; $band_bottom; $gap_margin)), distance: 0 }
                else
                  null
                end) as $focused_choice
              | ($focused_choice // ([
                  $clients[]
                  | select((.mapped // true) == true)
                  | select((.hidden // false) | not)
                  | select(on_monitor($monitor_id; $monitor_name))
                  | select(on_workspace($workspace_id))
                  | select((.address // "") != $focused_address)
                  | (.at[0] // 0) as $window_x
                  | (.at[1] // 0) as $window_y
                  | (.size[0] // 0) as $window_width
                  | (.size[1] // 0) as $window_height
                  | select($window_width >= $overlay_width)
                  | select(($window_y + $window_height) > $band_top and $window_y < $band_bottom)
                  | (max($window_x; $monitor_x)) as $left_bound
                  | (min(($window_x + $window_width - $overlay_width); ($monitor_x + $monitor_width - $overlay_width))) as $right_bound
                  | select($right_bound >= $left_bound)
                  | (clamp(($monitor_center - ($overlay_width / 2)); $left_bound; $right_bound)) as $left
                  | {
                      left: $left,
                      distance: (($left + ($overlay_width / 2) - $monitor_center) | abs)
                    }
                ] | min_by(.distance) // { left: $fallback_x })) as $choice
              | [$monitor_name, (($choice.left - $monitor_x) | floor)] | @tsv
            end
          ' || true
      )"

      if [[ -z "$placement" ]]; then
        exit 0
      fi

      read -r monitor left_margin <<EOF
      $placement
      EOF

      if [[ -z "''${monitor:-}" || -z "''${left_margin:-}" ]]; then
        exit 0
      fi

      ${silakka54LayerViewer} --place "$monitor" "$left_margin" || true
    '';
  };
  silakka54LayerViewerWatch = pkgs.writeShellApplication {
    name = "silakka54-layer-viewer-watch";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      socat
    ];
    text = ''
      set -euo pipefail

      find_socket() {
        local runtime_dir socket
        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

        if [[ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
          socket="$runtime_dir/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
          if [[ -S "$socket" ]]; then
            printf '%s\n' "$socket"
            return
          fi
        fi

        find "$runtime_dir/hypr" -mindepth 2 -maxdepth 2 -path '*/.socket2.sock' -print 2>/dev/null | sort | tail -n 1
      }

      place_now() {
        ${lib.getExe silakka54LayerViewerPlace} >/dev/null || true
      }

      pending_pid=""
      schedule_place() {
        local delay
        delay="''${1:-0.05}"
        if [[ -n "$pending_pid" ]] && kill -0 "$pending_pid" 2>/dev/null; then
          kill "$pending_pid" 2>/dev/null || true
        fi
        (
          sleep "$delay"
          place_now
        ) &
        pending_pid="$!"
      }

      while true; do
        socket="$(find_socket)"

        if [[ -z "$socket" ]]; then
          sleep 1
          continue
        fi

        place_now

        while IFS= read -r event; do
          case "$event" in
            activewindow*|focusedmon*|workspace*|activespecial*)
              place_now
              schedule_place 0.08
              ;;
            openwindow*|closewindow*|movewindow*|changefloatingmode*|fullscreen*|monitoradded*|monitorremoved*|configreloaded*)
              schedule_place
              ;;
          esac
        done < <(socat -u UNIX-CONNECT:"$socket" STDOUT 2>/dev/null)

        if [[ -n "$pending_pid" ]] && kill -0 "$pending_pid" 2>/dev/null; then
          kill "$pending_pid" 2>/dev/null || true
        fi
        pending_pid=""
        sleep 1
      done
    '';
  };
in
{
  imports = [ inputs.wired.homeManagerModules.default ];

  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "24.05";
  };

  age.rekey = {
    hostPubkey = lib.mkForce "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICuABSLmzF3xy8AUA1tqzy11jnkubwbcVALayATZ43fL conroy@brick";
  };

  corncheese = {
    development = {
      enable = true;
      electronics = {
        enable = true;
      };
      mechanical.enable = true;
      audio.enable = true;
      jetbrains = {
        enable = true;
        # clion.versionOverride = "2023.2.5";
      };
      rust.enable = false;
      vscode.enable = true;
      ssh = {
        enable = true;
        onePassword = true;
      };
      photo.enable = true;
    };
    scm = {
      git.enable = true;
    };
    theming = {
      enable = true;
      theme = "catppuccin";
      themeOverrides = {
        # Keep Stylix visibly separate from walbridge's runtime palette so
        # unsupported targets are obvious.
        stylixOverride = {
          base00 = "101010";
          base01 = "181818";
          base02 = "202020";
          base03 = "585858";
          base04 = "b0b0b0";
          base05 = "c8c8c8";
          base06 = "e0e0e0";
          base07 = "f5f5f5";
          base08 = "707070";
          base09 = "7a7a7a";
          base0A = "8a8a8a";
          base0B = "9a9a9a";
          base0C = "aaaaaa";
          base0D = "bababa";
          base0E = "cacaca";
          base0F = "dadada";
        };
      };
    };
    wm = {
      enable = true;
      nvidia = false;
      hyprpaper.enable = true;
      enableFancyEffects = true;
    };
    desktop = {
      enable = true;
      mail.enable = true;
      firefox.enable = false;
      chromium.enable = true;
      element.enable = true;
      media = {
        enable = true;
      };
    };
    shell = {
      enable = true;
      starship = true;
      p10k = false;
      direnv = true;
      zoxide = true;
      atuin = {
        enable = true;
        sync = true;
      };
      shells = [ "fish" ];
    };
    wezterm = {
      enable = true;
    };
    music = {
      enable = true;
    };
    games.minecraft = true;
  };
  andromeda = {
    development.enable = true;
  };

  programs.colorshell.enable = true;

  wayland.windowManager.hyprland.settings = {
    monitor = [
      {
        output = "desc: LG Electronics 27GN950 008NTJJ7W924";
        mode = "3840x2160@160";
        position = "0x0";
        scale = 1.33333;
        vrr = 3;
      }
      {
        output = "desc: Dell Inc. DELL U2720Q 8LXMZ13";
        mode = "3840x2160@60";
        position = "2880x0";
        scale = 1.33333;
        vrr = 0;
        bitdepth = 10;
      }
      {
        output = "";
        mode = "preferred";
        position = "auto";
        scale = 1;
      }
    ];
    animation = lib.mkAfter [
      {
        leaf = "layers";
        enabled = true;
        speed = 3;
        bezier = "wind";
        style = "slide";
      }
      {
        leaf = "layersIn";
        enabled = true;
        speed = 3;
        bezier = "wind";
        style = "slide";
      }
      {
        leaf = "layersOut";
        enabled = true;
        speed = 2;
        bezier = "wind";
        style = "slide";
      }
    ];
  };
  wayland.windowManager.hyprland.extraConfig = ''
    local silakka54_layer_viewer_control = ${luaString silakka54LayerViewerControl}
    local silakka54_layer_viewer_place = ${luaString (lib.getExe silakka54LayerViewerPlace)}
    local silakka54_layer_viewer_ready = true

    local function silakka54_layer_viewer_activity()
      if not silakka54_layer_viewer_ready then
        return
      end

      silakka54_layer_viewer_ready = false
      hl.exec_cmd(silakka54_layer_viewer_place .. " >/dev/null 2>&1; " .. silakka54_layer_viewer_control .. " activity")
      hl.timer(function()
        silakka54_layer_viewer_ready = true
      end, { timeout = 250, type = "oneshot" })
    end

    for keycode = 8, 255 do
      hl.bind("code:" .. keycode, silakka54_layer_viewer_activity, {
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
      })
    end

    hl.on("keybinds.submap", function(submap)
      if submap == "game" then
        hl.exec_cmd(silakka54_layer_viewer_control .. " hide")
      end
    end)

    hl.layer_rule({
      match = { namespace = "^silakka54-layer-viewer$" },
      blur = true,
      ignore_alpha = 0.2,
      animation = "slide",
    })
  '';

  stylix = {
    targets.hyprland.enable = false;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  manual.manpages.enable = false;

  home.packages = with pkgs; [
    gparted
    audacity
    # libreoffice-qt6-fresh  # https://github.com/NixOS/nixpkgs/issues/514113

    pciutils # lspci
    usbutils # lsusb
    # (uutils-coreutils.override { prefix = ""; }) # coreutils in rust

    ## Wine
    # winetricks (all versions)
    winetricks
    # native wayland support (unstable)
    wineWow64Packages.waylandFull
    samba
    silakka54
    silakka54LayerViewerPlace
    silakka54LayerViewerWatch
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  services.udiskie.enable = true;

  systemd.user.services.silakka54-firmware-prompt = {
    Unit = {
      Description = "Prompt before flashing stale Silakka54 firmware";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${silakka54FirmwarePrompt}";
    };
  };

  systemd.user.services.silakka54-sync = {
    Unit = {
      Description = "Reconcile Silakka54 keymap after Home Manager activation";
      After = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.silakka54} rebuild-switch";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.silakka54-layer-viewer = {
    Unit = {
      Description = "Silakka54 layer viewer overlay";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${silakka54LayerViewer} --hidden";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.silakka54-layer-viewer-watch = {
    Unit = {
      Description = "Place the Silakka54 layer viewer from Hyprland window state";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe silakka54LayerViewerWatch}";
      Restart = "always";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Enable the GPG Agent daemon.
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  programs.vifm = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };

  programs.btop = {
    enable = true;
  };

  programs.cava = {
    enable = true;
  };

  programs.gpg = {
    enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withPython3 = true;
    withRuby = true;
  };
  xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

  home.file = {
    ".config/nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/src/reovim";
    };
  };

  programs.vesktop = {
    enable = true;
  };
}
