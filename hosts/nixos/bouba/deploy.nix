{
  config,
  inputs,
  pkgs,
  ...
}:
let
  # Frame boot tooling validates canonical nixos-system-* paths and bootspecs.
  # Include deploy-rs's entrypoints in that output instead of wrapping it.
  activate = pkgs.writeShellScript "bouba-deploy-activate" ''
    set -euo pipefail
    cd /tmp
    action=switch
    if [[ "''${DRY_ACTIVATE:-}" == 1 ]]; then
      action=dry-activate
    elif [[ "''${BOOT:-}" == 1 ]]; then
      action=boot
    elif [[ "''${TEST:-}" == 1 ]]; then
      action=test
    fi
    exec "$PROFILE/bin/switch-to-configuration" "$action"
  '';
  deploy = inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  system.build.deploy = config.system.build.toplevel;
  system.systemBuilderCommands = ''
    ln -s ${activate} "$out/deploy-rs-activate"
    ln -s ${deploy}/bin/activate "$out/activate-rs"
  '';
}
