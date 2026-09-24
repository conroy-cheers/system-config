set -eu

if [ -e /sys/class/net/wlan0 ]; then
  # Also recovers a failed boot-time dependency job after the device appears.
  systemctl start --no-block wpa_supplicant-wlan0.service dhcpcd.service
  systemctl stop shrimpus-wifi-health.timer || true
  exit 0
fi

state=/run/shrimpus-wifi-health/attempts
attempts=0
if [ -f "$state" ]; then
  read -r attempts < "$state"
fi
if [ "$attempts" -ge 3 ]; then
  systemctl stop shrimpus-wifi-health.timer || true
  exit 0
fi
attempts=$((attempts + 1))
printf '%s\n' "$attempts" > "$state"
echo "wlan0 missing; recovery attempt $attempts/3"

# The vendor module can load successfully despite sprdwl_probe failing. Ask
# the platform bus to reprobe only an unbound device; do not unload a live BSP.
device=/sys/bus/platform/devices/unisoc_wifi
if [ -d "$device" ] && [ ! -L "$device/driver" ]; then
  echo unisoc_wifi > /sys/bus/platform/drivers_probe || true
fi
if [ ! -e /sys/class/net/wlan0 ]; then
  echo "Wi-Fi interface still missing; inspect SHRIMPUS/ on the SD FAT partition"
  if [ "$attempts" -ge 3 ]; then
    systemctl stop shrimpus-wifi-health.timer || true
    exit 0
  fi
  exit 1
fi
systemctl start --no-block wpa_supplicant-wlan0.service dhcpcd.service
systemctl stop shrimpus-wifi-health.timer || true
