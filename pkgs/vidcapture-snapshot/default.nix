{
  coreutils,
  ffmpeg-full,
  lib,
  writeShellApplication,
}:

writeShellApplication {
  name = "vidcapture-snapshot";

  text = ''
    set -euo pipefail

    usage() {
      while IFS= read -r line; do
        printf '%s\n' "$line"
      done <<HELP
    Usage:
      vidcapture-snapshot [-d DEVICE] [-f FORMAT] [-s WxH] [-r FPS] [-n N] [-R] -o OUTPUT

    Options:
      -d DEVICE   V4L2 device path (default: /dev/video0)
      -f FORMAT   Pixel format: mjpeg or yuyv422 (default: mjpeg)
      -s WxH      Frame size (default: 1920x1080)
      -r FPS      Framerate to negotiate with the device (default: 60)
      -n N        Discard the first N captured frames before saving (default: 8)
      -R          Skip the USB re-authorize before opening the device
      -o OUTPUT   Output image path (extension determines format: .png, .jpg, ...)
      -h          Show this help

    The USB capture device is re-authorized via sudo before each run, since the
    UGREEN UVC card otherwise hangs across consecutive opens. Pass -R to skip.
    HELP
    }

    reset_usb() {
      local dev=$1
      local name iface_path usb_path authorized
      name=$(${lib.getExe' coreutils "basename"} "$dev")
      iface_path=$(${lib.getExe' coreutils "readlink"} -f "/sys/class/video4linux/$name/device")
      usb_path=$(${lib.getExe' coreutils "dirname"} "$iface_path")
      authorized="$usb_path/authorized"
      [[ -e "$authorized" ]] || { printf 'vidcapture-snapshot: cannot find USB authorized at %s\n' "$authorized" >&2; return 1; }
      printf 0 | /run/wrappers/bin/sudo ${lib.getExe' coreutils "tee"} "$authorized" >/dev/null
      sleep 1
      printf 1 | /run/wrappers/bin/sudo ${lib.getExe' coreutils "tee"} "$authorized" >/dev/null
      local _
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -e "$dev" ]] && break
        sleep 0.5
      done
      sleep 2
    }

    device=/dev/video0
    format=mjpeg
    size=1920x1080
    fps=60
    discard=8
    reset=1
    output=

    while getopts ":d:f:s:r:n:Ro:h" opt; do
      case "$opt" in
        d) device=$OPTARG ;;
        f) format=$OPTARG ;;
        s) size=$OPTARG ;;
        r) fps=$OPTARG ;;
        n) discard=$OPTARG ;;
        R) reset=0 ;;
        o) output=$OPTARG ;;
        h) usage; exit 0 ;;
        \?) usage >&2; exit 2 ;;
      esac
    done

    [[ -n "$output" ]] || { usage >&2; printf '\nvidcapture-snapshot: -o OUTPUT is required\n' >&2; exit 2; }
    [[ -e "$device" ]] || { printf 'vidcapture-snapshot: %s does not exist\n' "$device" >&2; exit 1; }

    if [[ "$reset" == 1 ]]; then
      reset_usb "$device"
    fi

    select_filter="select=gte(n\\,$discard)"

    exec ${lib.getExe ffmpeg-full} \
      -hide_banner \
      -loglevel warning \
      -y \
      -analyzeduration 5M \
      -probesize 5M \
      -fflags +genpts+nobuffer \
      -f v4l2 \
      -input_format "$format" \
      -video_size "$size" \
      -framerate "$fps" \
      -i "$device" \
      -vf "$select_filter" \
      -fps_mode vfr \
      -frames:v 1 \
      -update 1 \
      "$output"
  '';

  derivationArgs = {
    meta = {
      description = "Capture a single frame from a V4L2 device to an image file";
      mainProgram = "vidcapture-snapshot";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };
}
