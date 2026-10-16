{
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    inputs.steam-frame-nixos.homeManagerModules.steamvr
  ];
  home = {
    username = "conroy";
    homeDirectory = "/home/conroy";
    stateVersion = "26.05";
  };
  corncheese.shell = {
    enable = true;
    hostname = "bouba";
    shells = [ "fish" ];
    starship = true;
    p10k = false;
    direnv = true;
    zoxide = true;
    atuin = {
      enable = true;
      sync = false;
    };
  };
  # Keep the Frame lightweight; workstation development suites stay disabled.
  corncheese.development.enable = false;
  andromeda.development.enable = false;
  corncheese.scm.git.enable = true;
  corncheese.theming = {
    enable = true;
    theme = "catppuccin";
  };
  programs.home-manager.enable = true;
  manual.manpages.enable = false;
  programs.atuin.settings.auto_sync = false;
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 1800;
  };
  programs.vifm.enable = true;
  programs.cava.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withPython3 = true;
    withRuby = true;
  };
  programs.ripgrep.enable = true;
  programs.btop.enable = true;
  programs.colorshell.enable = true;
  corncheese.wm = {
    enable = true;
    sessionMode = "nested";
    transparentBackground = config.programs.steamvr.nestedDesktop.transparent;
    enableFancyEffects = false;
  };
  # The Frame keeps ownership of Mesa, audio, login and the physical displays.
  programs.steamvr.nestedDesktop = {
    enable = true;
    name = "Corncheese Desktop";
    transparent = true;
    transport = "wayland";
    width = 1920;
    height = 1080;
    command = [
      "${config.wayland.windowManager.hyprland.package}/bin/start-hyprland"
      "--no-nixgl"
      "--path"
      "${config.wayland.windowManager.hyprland.package}/bin/Hyprland"
    ];
  };
  wayland.windowManager.hyprland.settings = {
    # Native Wayland advertises Gamescope's refresh rate as its preferred mode.
    monitor = lib.mkForce [
      {
        output = "";
        mode =
          if config.programs.steamvr.nestedDesktop.transport == "wayland" then
            "preferred"
          else
            "${toString config.programs.steamvr.nestedDesktop.width}x${toString config.programs.steamvr.nestedDesktop.height}@60";
        position = "auto";
        scale = 1;
      }
    ];
    config.animations.enabled = lib.mkForce false;
    # Gamescope's native XDG cursor plane is incomplete; include our cursor in
    # Hyprland's output texture instead.
    config.cursor.no_hardware_cursors = lib.mkIf (
      config.programs.steamvr.nestedDesktop.transport == "wayland"
    ) 1;
  };
  programs.steamvr.enable = true;
}
