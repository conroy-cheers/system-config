{
  coreutils,
  curl,
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
      done <<'HELP'
    Usage:
      vidcapture-snapshot [-i INPUT] [-w SECONDS] -o OUTPUT

    Options:
      -i INPUT    Snapshot URL or latest JPEG path (default:
                  $VIDCAPTURE_SNAPSHOT_SOURCE or http://127.0.0.1:39272/snapshot)
      -w SECONDS  Wait this long for the first service snapshot (default: 10)
      -o OUTPUT   Output image path, or - for stdout
      -h          Show this help

    Compatibility options from the old direct-device command (-d, -f, -s, -r,
    -n, and -R) are accepted but ignored. The background keepalive service owns
    the capture device, and snapshots are copied as JPEG bytes from its MJPEG
    stream.
    HELP
    }

    input=''${VIDCAPTURE_SNAPSHOT_SOURCE:-http://127.0.0.1:39272/snapshot}
    wait_seconds=10
    output=

    while getopts ":i:w:d:f:s:r:n:Ro:h" opt; do
      case "$opt" in
        i) input=$OPTARG ;;
        w) wait_seconds=$OPTARG ;;
        d | f | s | r | n | R) ;;
        o) output=$OPTARG ;;
        h) usage; exit 0 ;;
        \?) usage >&2; exit 2 ;;
      esac
    done

    [[ -n "$output" ]] || { usage >&2; printf '\nvidcapture-snapshot: -o OUTPUT is required\n' >&2; exit 2; }

    case "$input" in
      http://* | https://*)
        fetch_snapshot() {
          ${lib.getExe curl} --fail --silent --show-error --max-time 3 "$input"
        }

        if [[ "$output" == "-" ]]; then
          deadline=$((SECONDS + wait_seconds))
          until fetch_snapshot; do
            if (( SECONDS >= deadline )); then
              printf 'vidcapture-snapshot: no service snapshot available at %s\n' "$input" >&2
              exit 1
            fi
            sleep 0.1
          done
          exit 0
        fi

        dir=$(${lib.getExe' coreutils "dirname"} "$output")
        base=$(${lib.getExe' coreutils "basename"} "$output")
        tmp=$(${lib.getExe' coreutils "mktemp"} --tmpdir="$dir" ".$base.tmp.XXXXXX")
        cleanup() {
          rm -f "$tmp"
        }
        trap cleanup EXIT

        deadline=$((SECONDS + wait_seconds))
        until fetch_snapshot > "$tmp"; do
          rm -f "$tmp"
          tmp=$(${lib.getExe' coreutils "mktemp"} --tmpdir="$dir" ".$base.tmp.XXXXXX")
          if (( SECONDS >= deadline )); then
            printf 'vidcapture-snapshot: no service snapshot available at %s\n' "$input" >&2
            exit 1
          fi
          sleep 0.1
        done
        ${lib.getExe' coreutils "mv"} "$tmp" "$output"
        trap - EXIT
        ;;
      *)
        deadline=$((SECONDS + wait_seconds))
        while [[ ! -s "$input" ]]; do
          if (( SECONDS >= deadline )); then
            printf 'vidcapture-snapshot: no service snapshot available at %s\n' "$input" >&2
            exit 1
          fi
          sleep 0.1
        done

        if [[ "$output" == "-" ]]; then
          exec ${lib.getExe' coreutils "cat"} "$input"
        fi

        dir=$(${lib.getExe' coreutils "dirname"} "$output")
        base=$(${lib.getExe' coreutils "basename"} "$output")
        tmp=$(${lib.getExe' coreutils "mktemp"} --tmpdir="$dir" ".$base.tmp.XXXXXX")
        cleanup() {
          rm -f "$tmp"
        }
        trap cleanup EXIT

        ${lib.getExe' coreutils "cp"} "$input" "$tmp"
        ${lib.getExe' coreutils "mv"} "$tmp" "$output"
        trap - EXIT
        ;;
    esac
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
