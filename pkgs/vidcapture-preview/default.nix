{
  coreutils,
  ffmpeg-full,
  lib,
  writeShellApplication,
}:

writeShellApplication {
  name = "vidcapture-preview";

  text = ''
    set -euo pipefail

    usage() {
      while IFS= read -r line; do
        printf '%s\n' "$line"
      done <<HELP
    Usage:
      vidcapture-preview [-d DEVICE] [-f FORMAT] [-s WxH] [-r FPS] [-R] [-- FFPLAY_ARGS...]

    Options:
      -d DEVICE   V4L2 device path (default: /dev/video0)
      -f FORMAT   Pixel format: mjpeg or yuyv422 (default: mjpeg)
      -s WxH      Frame size (default: 1920x1080)
      -r FPS      Framerate (default: 60)
      -R          Skip the USB re-authorize before opening the device
      -h          Show this help

    The USB capture device is re-authorized via sudo before each run, since the
    UGREEN UVC card otherwise hangs across consecutive opens. Pass -R to skip.

    Anything after "--" is forwarded to ffplay.
    HELP
    }

    reset_usb() {
      local dev=$1
      local name iface_path usb_path authorized
      name=$(${lib.getExe' coreutils "basename"} "$dev")
      iface_path=$(${lib.getExe' coreutils "readlink"} -f "/sys/class/video4linux/$name/device")
      usb_path=$(${lib.getExe' coreutils "dirname"} "$iface_path")
      authorized="$usb_path/authorized"
      [[ -e "$authorized" ]] || { printf 'vidcapture-preview: cannot find USB authorized at %s\n' "$authorized" >&2; return 1; }
      printf 0 | /run/wrappers/bin/sudo ${lib.getExe' coreutils "tee"} "$authorized" >/dev/null
      sleep 1
      printf 1 | /run/wrappers/bin/sudo ${lib.getExe' coreutils "tee"} "$authorized" >/dev/null
      # wait for /dev/videoN to reappear, then settle
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
    reset=1

    while getopts ":d:f:s:r:Rh" opt; do
      case "$opt" in
        d) device=$OPTARG ;;
        f) format=$OPTARG ;;
        s) size=$OPTARG ;;
        r) fps=$OPTARG ;;
        R) reset=0 ;;
        h) usage; exit 0 ;;
        \?) usage >&2; exit 2 ;;
      esac
    done
    shift $((OPTIND - 1))

    [[ -e "$device" ]] || { printf 'vidcapture-preview: %s does not exist\n' "$device" >&2; exit 1; }

    if [[ "$reset" == 1 ]]; then
      reset_usb "$device"
    fi

    exec ${lib.getExe' ffmpeg-full "ffplay"} \
      -hide_banner \
      -loglevel warning \
      -f v4l2 \
      -input_format "$format" \
      -video_size "$size" \
      -framerate "$fps" \
      -fflags nobuffer \
      -flags low_delay \
      -framedrop \
      -infbuf \
      -window_title "vidcapture-preview $device $format $size@$fps" \
      -i "$device" \
      "$@"
  '';

  derivationArgs = {
    meta = {
      description = "Live ffplay preview of a V4L2 capture device with no playback UI";
      mainProgram = "vidcapture-preview";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };
}
