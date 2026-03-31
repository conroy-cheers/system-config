{
  lib,
  callPackage,
  jq,
  runCommand,
  writeShellApplication,
  sketchybar,
  yabai,
}:
let
  sketchybar-toggle = callPackage ../sketchybar-toggle { };

  sketchybar-config = runCommand "minimal-sketchybar-config" { } ''
    mkdir -p "$out/plugins"
    cp ${./sketchybarrc} "$out/sketchybarrc"
    cp ${./plugins/clock.sh} "$out/plugins/clock.sh"
    cp ${./plugins/space.sh} "$out/plugins/space.sh"
    chmod a+x "$out/sketchybarrc" "$out/plugins/clock.sh" "$out/plugins/space.sh"
  '';
in
writeShellApplication {
  name = "sketchybar";

  runtimeInputs = [
    jq
    sketchybar
    sketchybar-toggle
    yabai
  ];

  text = ''
    if [ "$#" -gt 0 ]; then
      exec ${lib.getExe sketchybar} "$@"
    fi

    exec ${lib.getExe sketchybar} --config ${sketchybar-config}/sketchybarrc
  '';

  derivationArgs = {
    passthru.config = sketchybar-config;
  };
}
