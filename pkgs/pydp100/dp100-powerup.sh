#!@bash@
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dp100-powerup [--config PATH]

Options:
  -c, --config PATH  Path to config.txt (default: ./config.txt,
                     then $XDG_CONFIG_HOME/pydp100/config.txt,
                     then ~/.config/pydp100/config.txt)
  -h, --help         Show this help
USAGE
}

config_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--config)
      if [ "$#" -lt 2 ]; then
        echo "Missing path for --config" >&2
        exit 2
      fi
      config_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$config_path" ]; then
  if [ -f "./config.txt" ]; then
    config_path="$(pwd)/config.txt"
  elif [ -n "${XDG_CONFIG_HOME:-}" ] && [ -f "${XDG_CONFIG_HOME}/pydp100/config.txt" ]; then
    config_path="${XDG_CONFIG_HOME}/pydp100/config.txt"
  elif [ -n "${HOME:-}" ] && [ -f "${HOME}/.config/pydp100/config.txt" ]; then
    config_path="${HOME}/.config/pydp100/config.txt"
  else
    echo "config.txt not found. Use --config or create ~/.config/pydp100/config.txt" >&2
    exit 2
  fi
fi

if [ ! -f "$config_path" ]; then
  echo "config not found: $config_path" >&2
  exit 2
fi

tmpdir="$(@mktemp@ -d)"
cleanup() {
  @rm@ -rf "$tmpdir"
}
trap cleanup EXIT

@cp@ "$config_path" "$tmpdir/config.txt"

export PYTHONPATH="@pythonpath@${PYTHONPATH:+:$PYTHONPATH}"
cd "$tmpdir"
@python@ @script@
exit $?
