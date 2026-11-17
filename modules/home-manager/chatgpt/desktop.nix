{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.chatgpt;
  desktopSetups = lib.filterAttrs (_: setup: setup.enable && setup.desktop.enable) cfg.profiles;
  desktopPackage =
    setup:
    pkgs.runCommand setup.desktop.command
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = setup.desktop.command;
      }
      ''
        mkdir -p "$out/bin" "$out/share/icons"
        ln -s ${setup.desktop.package}/share/icons/hicolor "$out/share/icons/hicolor"
        makeWrapper ${lib.getExe' setup.desktop.package "codex-desktop"} \
          "$out/bin/${setup.desktop.command}" \
          --set CODEX_CLI_PATH ${lib.escapeShellArg (lib.getExe setup.finalPackage)} \
          --set CODEX_HOME ${lib.escapeShellArg setup.codexHome} \
          --set CODEX_APP_ID ${lib.escapeShellArg setup.desktop.appId} \
          --set CODEX_LINUX_APP_ID ${lib.escapeShellArg setup.desktop.appId} \
          --set CODEX_LINUX_APP_DISPLAY_NAME ${lib.escapeShellArg setup.desktop.name} \
          --set CODEX_ELECTRON_USER_DATA_PATH ${lib.escapeShellArg setup.desktop.userDataDir} \
          --set CODEX_WEBVIEW_PORT ${toString setup.desktop.webviewPort} \
          --set CHROME_DESKTOP ${lib.escapeShellArg "${setup.desktop.appId}.desktop"} \
          --set BAMF_DESKTOP_FILE_HINT ${lib.escapeShellArg "${config.xdg.dataHome}/applications/${setup.desktop.appId}.desktop"} \
          --run ${
            lib.escapeShellArg (
              lib.optionalString (
                setup.relay.enable && setup.relay.catalog.enable
              ) "${lib.getExe setup.relay.catalog.refreshPackage} --if-stale --allow-missing"
            )
          } \
          --run ${lib.escapeShellArg "${pkgs.coreutils}/bin/mkdir -p ${
            lib.escapeShellArgs [
              setup.codexHome
              setup.desktop.userDataDir
            ]
          }"}
      '';
in
{
  options.programs.chatgpt.profiles = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          config.desktop.finalPackage = desktopPackage config;
        }
      )
    );
  };
  config = lib.mkIf cfg.enable {
    home.packages = map (s: s.desktop.finalPackage) (builtins.attrValues desktopSetups);
    xdg.desktopEntries = lib.mapAttrs' (
      _: setup:
      lib.nameValuePair setup.desktop.appId {
        name = setup.desktop.name;
        genericName = "AI assistant";
        exec = "${lib.getExe setup.desktop.finalPackage} %U";
        icon = "codex-desktop";
        terminal = false;
        categories = [ "Development" ];
        mimeType = lib.optionals (setup.command == "codex") [
          "x-scheme-handler/codex"
          "x-scheme-handler/codex-browser-sidebar"
        ];
        settings.StartupWMClass = setup.desktop.appId;
      }
    ) desktopSetups;
  };
}
