{ pkgs, inputs, ... }:
let
  vmSystem = import "${inputs.self}/hosts/nixos/panda/vm-system.nix" { inherit inputs; };
in
pkgs.testers.runNixOSTest {
  name = "panda-smoke";

  nodes.machine = { ... }: {
    imports = vmSystem.modules;
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("klipper.service")
    machine.wait_for_unit("moonraker.service")
    machine.wait_for_unit("panda-can0.service")

    machine.succeed("systemctl is-active nginx.service")
    machine.succeed("systemctl is-active klipper.service")
    machine.succeed("systemctl is-active moonraker.service")
    machine.succeed("ip -details link show can0 | grep -F 'vcan'")
    machine.succeed("systemctl show -p After klipper.service | grep -F panda-can0.service")

    machine.succeed("test -f /var/lib/moonraker/config/printer.cfg")
    machine.succeed("test -f /var/lib/moonraker/config/mainsail.cfg")
    machine.succeed("test -f /var/lib/moonraker/config/sb2040v2.cfg")
    machine.succeed("test -f /var/lib/moonraker/config/stealthburner_leds.cfg")
    machine.succeed("test -L /home/pi/gcode_files")
    machine.succeed("test -L /home/pi/klipper_config")

    machine.succeed("grep -F 'host:0.0.0.0' /etc/moonraker.cfg")
    machine.succeed("grep -F 'https://panda.home.conroycheers.me' /etc/moonraker.cfg")

    machine.succeed("curl -sf http://127.0.0.1/ | grep -Fi mainsail")
  '';
}
