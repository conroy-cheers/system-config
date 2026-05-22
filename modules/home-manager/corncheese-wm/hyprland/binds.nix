{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.corncheese.wm;
  colorshellEnabled = lib.attrByPath [ "programs" "colorshell" "enable" ] false config;
  lockCommand = if colorshellEnabled then "colorshell lock" else "hyprlock";

  lua = lib.generators.mkLuaInline;
  luaString = builtins.toJSON;

  bind = key: dispatcher: {
    _args = [
      key
      dispatcher
    ];
  };

  bindWith = key: dispatcher: opts: {
    _args = [
      key
      dispatcher
      opts
    ];
  };

  bindExec = key: command: bind key (lua "hl.dsp.exec_cmd(${luaString command})");
  mod = suffix: lua ''mod .. " + ${suffix}"'';
in
{
  wayland.windowManager.hyprland.settings = lib.mkIf cfg.enable {
    mod = {
      _var = "ALT";
    };

    # Mouse bindings.
    bind = [
      (bindWith (mod "mouse:272") (lua "hl.dsp.window.drag()") { mouse = true; })
      (bindWith (mod "mouse:273") (lua "hl.dsp.window.resize()") { mouse = true; })

      # Window/Session actions.
      (bind (mod "Q") (lua "hl.dsp.window.close()"))
      (bind (mod "W") (lua ''hl.dsp.window.fullscreen({ mode = "maximized" })''))
      (bind (mod "SHIFT + W") (lua "hl.dsp.window.fullscreen()"))
      (bind (mod "E") (lua ''hl.dsp.window.float({ action = "toggle" })''))
      (bind (mod "CTRL + delete") (lua "hl.dsp.exit()"))

      # Dwindle
      (bind (mod "O") (lua ''hl.dsp.layout("togglesplit")''))
      (bind (mod "P") (lua "hl.dsp.window.pseudo()"))

      # Lock screen
      (bindExec (mod "Escape") lockCommand)

      # Application shortcuts.
      (bindExec (mod "Return") "ghostty")
      (bindExec (mod "SHIFT + Return") "ghostty '--title=ghostty-floating'")
      (bindExec (mod "F") "chromium")
      (bindExec (mod "T") "thunar")

      # Special workspace
      (bind (mod "S") (lua "hl.dsp.workspace.toggle_special()"))
      (bind (mod "CTRL + S") (lua "hl.dsp.workspace.toggle_special()"))
      (bind (mod "SHIFT + S") (lua ''hl.dsp.window.move({ workspace = "special", follow = false })''))

      # Screenshot
      (bindExec (mod "SHIFT + PRINT") "grimblast copy area")
      (bindExec (mod "PRINT") "grimblast copysave screen")

      # Move window focus with vim keys.
      (bind (mod "h") (lua ''hl.dsp.focus({ direction = "left" })''))
      (bind (mod "l") (lua ''hl.dsp.focus({ direction = "right" })''))
      (bind (mod "k") (lua ''hl.dsp.focus({ direction = "up" })''))
      (bind (mod "j") (lua ''hl.dsp.focus({ direction = "down" })''))

      # Swap windows with vim keys
      (bind (mod "SHIFT + h") (lua ''hl.dsp.window.swap({ direction = "left" })''))
      (bind (mod "SHIFT + l") (lua ''hl.dsp.window.swap({ direction = "right" })''))
      (bind (mod "SHIFT + k") (lua ''hl.dsp.window.swap({ direction = "up" })''))
      (bind (mod "SHIFT + j") (lua ''hl.dsp.window.swap({ direction = "down" })''))

      # Move monitor focus.
      (bind (mod "TAB") (lua ''hl.dsp.focus({ monitor = "+1" })''))

      # Switch workspaces.
      (bindExec (mod "1") "hyprworkspace 1")
      (bindExec (mod "2") "hyprworkspace 2")
      (bindExec (mod "3") "hyprworkspace 3")
      (bindExec (mod "4") "hyprworkspace 4")
      (bindExec (mod "5") "hyprworkspace 5")
      (bindExec (mod "6") "hyprworkspace 6")
      (bindExec (mod "7") "hyprworkspace 7")
      (bindExec (mod "8") "hyprworkspace 8")
      (bindExec (mod "9") "hyprworkspace 9")

      (bind (mod "CTRL + h") (lua ''hl.dsp.focus({ workspace = "r-1" })''))
      (bind (mod "CTRL + l") (lua ''hl.dsp.focus({ workspace = "r+1" })''))

      # Scroll through monitor workspaces with mod + scroll
      (bind (mod "mouse_down") (lua ''hl.dsp.focus({ workspace = "r-1" })''))
      (bind (mod "mouse_up") (lua ''hl.dsp.focus({ workspace = "r+1" })''))
      (bind (mod "mouse:274") (lua "hl.dsp.window.close()"))

      # Move active window to a workspace.
      (bind (mod "SHIFT + 1") (lua "hl.dsp.window.move({ workspace = 1 })"))
      (bind (mod "SHIFT + 2") (lua "hl.dsp.window.move({ workspace = 2 })"))
      (bind (mod "SHIFT + 3") (lua "hl.dsp.window.move({ workspace = 3 })"))
      (bind (mod "SHIFT + 4") (lua "hl.dsp.window.move({ workspace = 4 })"))
      (bind (mod "SHIFT + 5") (lua "hl.dsp.window.move({ workspace = 5 })"))
      (bind (mod "SHIFT + 6") (lua "hl.dsp.window.move({ workspace = 6 })"))
      (bind (mod "SHIFT + 7") (lua "hl.dsp.window.move({ workspace = 7 })"))
      (bind (mod "SHIFT + 8") (lua "hl.dsp.window.move({ workspace = 8 })"))
      (bind (mod "SHIFT + 9") (lua "hl.dsp.window.move({ workspace = 9 })"))
      (bind (mod "SHIFT + 0") (lua "hl.dsp.window.move({ workspace = 10 })"))
      (bind (mod "CTRL + SHIFT + l") (lua ''hl.dsp.window.move({ workspace = "r+1" })''))
      (bind (mod "CTRL + SHIFT + h") (lua ''hl.dsp.window.move({ workspace = "r-1" })''))

      # Resize submap
      (bind (mod "R") (lua ''
        function()
          hl.exec_cmd("echo -n Resize > /tmp/hypr_submap")
          hl.dispatch(hl.dsp.submap("resize"))
        end
      ''))
    ]
    ++ lib.optionals colorshellEnabled [
      (bindExec (mod "F5") "colorshell reload")
      (bindExec (mod "Space") "colorshell runner")
      (bindExec (mod "V") "colorshell runner '>'")
      (bindExec (mod "M") "colorshell toggle center-window")
    ]
    ++ [
      (bindWith "XF86AudioRaiseVolume" (lua ''hl.dsp.exec_cmd("pulsemixer --change-volume +5")'') {
        repeating = true;
      })
      (bindWith "XF86AudioLowerVolume" (lua ''hl.dsp.exec_cmd("pulsemixer --change-volume -5")'') {
        repeating = true;
      })
      (bindWith "XF86MonBrightnessUp" (lua ''hl.dsp.exec_cmd("brightnessctl s +5%")'') {
        repeating = true;
      })
      (bindWith "XF86MonBrightnessDown" (lua ''hl.dsp.exec_cmd("brightnessctl s 5%-")'') {
        repeating = true;
      })
      (bindWith (mod "SUPER + k") (lua ''hl.dsp.exec_cmd("pulsemixer --change-volume +5")'') {
        repeating = true;
      })
      (bindWith (mod "SUPER + j") (lua ''hl.dsp.exec_cmd("pulsemixer --change-volume -5")'') {
        repeating = true;
      })
    ];

    define_submap = [
      {
        _args = [
          "resize"
          (lua ''
            function()
              hl.bind("l", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
              hl.bind("h", hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
              hl.bind("k", hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
              hl.bind("j", hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
              hl.bind("escape", function()
                hl.exec_cmd("truncate -s 0 /tmp/hypr_submap")
                hl.dispatch(hl.dsp.submap("reset"))
              end)
            end
          '')
        ];
      }
      {
        _args = [
          "game"
          (lua ''
            function()
              hl.bind(mod .. " + Q", hl.dsp.window.close())
              hl.bind(mod .. " + CTRL + delete", hl.dsp.exit())
              hl.bind(mod .. " + 1", hl.dsp.exec_cmd("hyprworkspace 1"))
              hl.bind(mod .. " + 2", hl.dsp.exec_cmd("hyprworkspace 2"))
              hl.bind(mod .. " + 3", hl.dsp.exec_cmd("hyprworkspace 3"))
              hl.bind(mod .. " + 4", hl.dsp.exec_cmd("hyprworkspace 4"))
              hl.bind(mod .. " + 5", hl.dsp.exec_cmd("hyprworkspace 5"))
              hl.bind(mod .. " + 6", hl.dsp.exec_cmd("hyprworkspace 6"))
              hl.bind(mod .. " + 7", hl.dsp.exec_cmd("hyprworkspace 7"))
              hl.bind(mod .. " + 8", hl.dsp.exec_cmd("hyprworkspace 8"))
              hl.bind(mod .. " + 9", hl.dsp.exec_cmd("hyprworkspace 9"))
              hl.bind(mod .. " + CTRL + h", hl.dsp.focus({ workspace = "r-1" }))
              hl.bind(mod .. " + CTRL + l", hl.dsp.focus({ workspace = "r+1" }))
              hl.bind(mod .. " + CTRL + S", hl.dsp.workspace.toggle_special())
              hl.bind(mod .. " + SHIFT + W", hl.dsp.window.fullscreen())
              hl.bind("SHIFT + F10", hl.dsp.exec_cmd("/home/conroy/src/erss/tools/mark_erss_state.sh /tmp/erss-watch-mark 'visual glitch observed'"))
            end
          '')
        ];
      }
    ];
  };
}
