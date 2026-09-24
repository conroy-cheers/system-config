set -eu

# Capture early boot only; avoid writing to the SD card every minute forever.
read -r uptime _ < /proc/uptime
if [ "${uptime%%.*}" -gt 900 ]; then
  exit 0
fi
mountpoint -q /boot/firmware
base=/boot/firmware/SHRIMPUS
mkdir -p "$base"
read -r boot_id < /proc/sys/kernel/random/boot_id
previous_id=
if [ -f "$base/current/boot-id" ]; then
  read -r previous_id < "$base/current/boot-id"
fi
if [ "$previous_id" != "$boot_id" ]; then
  rm -rf "$base/previous"
  if [ -d "$base/current" ]; then
    mv "$base/current" "$base/previous"
  fi
fi
mkdir -p "$base/current"
printf '%s\n' "$boot_id" > "$base/current/boot-id"

# Never copy credential files or dump the process environment.
{
  date --iso-8601=seconds
  printf 'Boot ID: %s\n' "$boot_id"
  uname -a
  printf '\nMemory\n'
  head -n 5 /proc/meminfo
  printf '\nNetwork\n'
  ip -br address
  ip route
  printf '\nServices\n'
  systemctl --no-pager --full status shrimpus-wifi-secrets \
    shrimpus-wifi-health wpa_supplicant-wlan0 dhcpcd sshd || true
  printf '\nFailed units\n'
  systemctl --no-pager --failed || true
} > "$base/current/status.txt.tmp" 2>&1
mv "$base/current/status.txt.tmp" "$base/current/status.txt"

journalctl --no-pager -b -k -n 800 | tail -c 1048576 > "$base/current/kernel.txt.tmp"
mv "$base/current/kernel.txt.tmp" "$base/current/kernel.txt"
journalctl --no-pager -b -n 400 \
  -u shrimpus-wifi-secrets -u shrimpus-wifi-health \
  -u wpa_supplicant-wlan0 -u dhcpcd -u sshd \
  | tail -c 1048576 > "$base/current/network.txt.tmp"
mv "$base/current/network.txt.tmp" "$base/current/network.txt"
sync -f "$base"
