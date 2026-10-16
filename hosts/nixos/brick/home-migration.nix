{ pkgs, ... }:

{
  # One-time final transfer before mounting the new home. The original home and
  # both read-only snapshots stay on cryptroot until the migration is verified.
  systemd.services.home-migration = {
    description = "Finish moving home to the encrypted Samsung SSD";
    requiredBy = [ "home.mount" ];
    before = [
      "home.mount"
      "shutdown.target"
    ];
    after = [ "systemd-cryptsetup@crypthome.service" ];
    requires = [ "systemd-cryptsetup@crypthome.service" ];
    conflicts = [ "shutdown.target" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "!/persist/home-migration/complete";
      RequiresMountsFor = [
        "/nix"
        "/persist"
      ];
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      PrivateMounts = true;
      TimeoutStartSec = "infinity";
      RuntimeDirectory = "home-migration";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
    };
    path = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.gawk
      pkgs.util-linux
    ];
    script = ''
      set -euo pipefail
      test -e /persist/home-migration/base-complete
      if mountpoint -q /home; then
        echo "Home migration requires a boot with /home unmounted." >&2
        exit 1
      fi
      old=/run/home-migration/old
      new=/run/home-migration/new
      base=home-migration-base-20261016
      final=home-migration-final-20261016
      mkdir -p "$old" "$new"
      mount -t btrfs -o subvolid=5,noatime /dev/mapper/cryptroot "$old"
      trap 'umount "$old"' EXIT
      mount -t btrfs -o subvolid=5,compress=zstd,noatime /dev/mapper/crypthome "$new"
      trap 'umount "$new"; umount "$old"' EXIT

      # Snapshots do not recursively include nested subvolumes.
      test -z "$(btrfs subvolume list -o "$old/home")"

      uuid() {
        btrfs subvolume show "$1" | awk '$1 == "UUID:" { print $2 }'
      }
      received_uuid() {
        btrfs subvolume show "$1" | awk '$1 == "Received" && $2 == "UUID:" { print $3 }'
      }

      # An incremental stream must use the exact unchanged snapshot received
      # during the initial copy, including after an interrupted boot.
      test "$(uuid "$old/$base")" = "$(received_uuid "$new/$base")"
      test "$(btrfs property get -ts "$new/$base" ro)" = "ro=true"
      if ! btrfs subvolume show "$old/$final" >/dev/null 2>&1; then
        btrfs subvolume snapshot -r "$old/home" "$old/$final"
      fi

      if btrfs subvolume show "$new/$final" >/dev/null 2>&1; then
        if test "$(received_uuid "$new/$final")" != "$(uuid "$old/$final")"; then
          # A failed receive leaves a writable, incomplete subvolume.
          test "$(btrfs property get -ts "$new/$final" ro)" = "ro=false"
          btrfs subvolume delete "$new/$final"
        fi
      fi
      if ! btrfs subvolume show "$new/$final" >/dev/null 2>&1; then
        btrfs send --compressed-data --proto 2 -p "$old/$base" "$old/$final" |
          btrfs receive "$new"
      fi
      test "$(uuid "$old/$final")" = "$(received_uuid "$new/$final")"
      test "$(btrfs property get -ts "$new/$final" ro)" = "ro=true"

      if ! btrfs subvolume show "$new/home" >/dev/null 2>&1; then
        btrfs subvolume snapshot "$new/$final" "$new/home"
      fi
      test "$(btrfs subvolume show "$new/home" | awk '$1 == "Parent" && $2 == "UUID:" { print $3 }')" = "$(uuid "$new/$final")"
      test "$(btrfs property get -ts "$new/home" ro)" = "ro=false"
      btrfs filesystem sync "$new"
      touch /persist/home-migration/complete
      sync -f /persist/home-migration/complete
    '';
  };

  systemd.services.home-migration-verify = {
    description = "Verify home is running from the new Samsung SSD";
    wantedBy = [ "multi-user.target" ];
    requires = [ "home.mount" ];
    after = [ "home.mount" ];
    unitConfig.ConditionPathExists = [
      "/persist/home-migration/complete"
      "!/persist/home-migration/verified"
    ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    path = [
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.util-linux
    ];
    script = ''
      set -euo pipefail
      test "$(findmnt -n -o UUID --target /home)" = 76191acd-293f-41d0-90f7-908439283cbd
      test "$(findmnt -n -o FSROOT --target /home)" = /home
      test -d /home/conroy
      probe=$(mktemp /home/.home-migration-check.XXXXXX)
      trap 'rm -f "$probe"' EXIT
      printf 'home migration write check\n' > "$probe"
      sync -f "$probe"
      test "$(cat "$probe")" = 'home migration write check'
      {
        date --iso-8601=seconds
        findmnt --target /home
        btrfs subvolume show /home
        stat -c '%u:%g %a %n' /home/conroy
      } > /persist/home-migration/verified.tmp
      mv /persist/home-migration/verified.tmp /persist/home-migration/verified
      sync -f /persist/home-migration/verified
    '';
  };
}
