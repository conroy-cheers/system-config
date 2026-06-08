{
  inputs,
  lib,
  pkgs,
  config,
  osConfig ? { },
  ...
}:

let
  luaString = builtins.toJSON;
  hyprlandPackage = osConfig.programs.hyprland.package or pkgs.hyprland;
  keyboardLayerViewerProfiles = pkgs.writeText "keyboard-layer-viewer-profiles.json" (
    builtins.toJSON {
      keyboards = [
        {
          id = "silakka54";
          name = "Silakka54";
          vid = "0xfeed";
          pid = "0x1212";
          info = "${pkgs.silakka54}/share/silakka54/keymap/info.json";
          layers = "${pkgs.silakka54}/share/silakka54/keymap/keymap.yaml";
          current_layer_hid = true;
        }
        {
          id = "logitech-pro-x-tkl";
          name = "Logitech PRO X TKL";
          vid = "0x046d";
          pid = "0xc339";
          info = "${../keyboard-layer-viewer/qwerty-tkl-info.json}";
          layers = "${../keyboard-layer-viewer/qwerty-tkl.yaml}";
          current_layer_hid = false;
        }
      ];
    }
  );
  keyboardLayerViewerHyprlandPlugin = pkgs.keyboard-layer-viewer-hyprland-plugin.override {
    hyprland = hyprlandPackage;
  };
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
  keyboardLayerViewer = lib.getExe pkgs.keyboard-layer-viewer;
  keyboardLayerViewerControl = pkgs.writeShellScript "keyboard-layer-viewer-control" ''
    set -eu

    command="''${1:?usage: keyboard-layer-viewer-control <activity|hide|refresh-placement|place MONITOR LEFT_MARGIN>}"
    socket="''${XDG_RUNTIME_DIR:?}/keyboard-layer-viewer.sock"

    case "$command" in
      activity)
        ${lib.getExe' pkgs.systemd "systemctl"} --user start keyboard-layer-viewer.service
        tries=0
        while [ ! -S "$socket" ] && [ "$tries" -lt 40 ]; do
          tries=$((tries + 1))
          ${lib.getExe' pkgs.coreutils "sleep"} 0.05
        done
        ;;
      hide)
        ;;
      refresh-placement)
        ;;
      place)
        monitor="''${2:?usage: keyboard-layer-viewer-control place MONITOR LEFT_MARGIN}"
        left_margin="''${3:?usage: keyboard-layer-viewer-control place MONITOR LEFT_MARGIN}"
        ;;
      *)
        echo "unsupported keyboard-layer-viewer command: $command" >&2
        exit 64
        ;;
    esac

    if [ ! -S "$socket" ]; then
      exit 0
    fi

    case "$command" in
      activity)
        ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --refresh-placement || true
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --activity
        ;;
      place)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --place "$monitor" "$left_margin"
        ;;
      refresh-placement)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --refresh-placement
        ;;
      *)
        exec ${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} "--$command"
        ;;
    esac
  '';
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
  wayland.windowManager.hyprland.plugins = lib.mkAfter [
    keyboardLayerViewerHyprlandPlugin
  ];
  home.activation.loadKeyboardLayerViewerHyprlandPlugin = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ -d "$runtime_dir/hypr" ]]; then
      for instance in $(${hyprlandPackage}/bin/hyprctl instances -j | ${lib.getExe pkgs.jq} -r '.[].instance'); do
        if ! ${hyprlandPackage}/bin/hyprctl -i "$instance" plugin list | ${lib.getExe pkgs.gnugrep} -q 'Plugin keyboard-layer-viewer-hyprland-plugin'; then
          ${hyprlandPackage}/bin/hyprctl -i "$instance" plugin load ${keyboardLayerViewerHyprlandPlugin}/lib/libkeyboard-layer-viewer-hyprland-plugin.so >/dev/null || true
        fi
      done
    fi
  '';
  wayland.windowManager.hyprland.extraConfig = ''
    local keyboard_layer_viewer_control = ${luaString keyboardLayerViewerControl}
    local keyboard_layer_viewer_ready = true

    local function keyboard_layer_viewer_activity()
      if not keyboard_layer_viewer_ready then
        return
      end

      keyboard_layer_viewer_ready = false
      hl.exec_cmd(keyboard_layer_viewer_control .. " refresh-placement; " .. keyboard_layer_viewer_control .. " activity")
      hl.timer(function()
        keyboard_layer_viewer_ready = true
      end, { timeout = 250, type = "oneshot" })
    end

    for keycode = 8, 255 do
      hl.bind("code:" .. keycode, keyboard_layer_viewer_activity, {
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
      })
    end

    hl.on("keybinds.submap", function(submap)
      if submap == "game" then
        hl.exec_cmd(keyboard_layer_viewer_control .. " hide")
      end
    end)

    hl.layer_rule({
      match = { namespace = "^keyboard-layer-viewer$" },
      blur = true,
      ignore_alpha = 0.4,
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
    keyboard-layer-viewer
    silakka54
  ];

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  services.udiskie.enable = true;

  systemd.user.services.silakka54-firmware-prompt = {
    Unit = {
      Description = "Prompt before flashing stale Silakka54 firmware";
      After = [ "graphical-session.target" ];
      X-SwitchMethod = "keep-old";
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

  systemd.user.services.keyboard-layer-viewer = {
    Unit = {
      Description = "Keyboard layer viewer overlay";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${keyboardLayerViewer} --profiles ${keyboardLayerViewerProfiles} --hidden";
      Restart = "on-failure";
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
