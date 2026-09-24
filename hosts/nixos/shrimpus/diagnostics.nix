{ pkgs, ... }:
{
  sdImage.populateFirmwareCommands = ''
    mkdir -p firmware/SHRIMPUS
    cat > firmware/SHRIMPUS/READ-ME.txt <<'EOF'
    shrimpus boot diagnostics

    Linux saves current/status.txt, kernel.txt and network.txt here starting
    about 30 seconds into boot, then again after 2, 5 and 10 minutes.
    The previous boot's snapshot is kept in previous/.
    No current/ directory means the exporter has not run successfully. It
    does not distinguish a bootloader, kernel, initrd or mount failure.
    These files contain network names/addresses and logs, but no key files.
    EOF
  '';

  services.journald.settings.Journal = {
    Storage = "persistent";
    SystemMaxUse = "100M";
    RuntimeMaxUse = "32M";
    SyncIntervalSec = "60s";
  };

  systemd.services.shrimpus-boot-diagnostics = {
    description = "Save boot diagnostics to the SD card FAT partition";
    after = [ "systemd-journald.service" ];
    unitConfig.RequiresMountsFor = "/boot/firmware";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30s";
      UMask = "0077";
    };
    path = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.iproute2
      pkgs.util-linux
    ];
    script = builtins.readFile ./boot-diagnostics.sh;
  };
  systemd.timers.shrimpus-boot-diagnostics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = [
        "30s"
        "2min"
        "5min"
        "10min"
      ];
    };
  };
}
