{
  coreutils,
  gawk,
  gnugrep,
  lib,
  libguestfs-with-appliance,
  openssh,
  writeShellApplication,
  zstd,
}:

writeShellApplication {
  name = "extract-image";

  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    libguestfs-with-appliance
    openssh
    zstd
  ];

  text = ''
    set -euo pipefail

    usage() {
      cat <<'EOF'
    Usage:
      extract-image --image IMAGE --host-privkey KEY -o OUTPUT [--expected-host-pubkey PUBKEY] [--force]

    Description:
      Copies or decompresses a NixOS SD image to OUTPUT, then injects
      /etc/ssh/ssh_host_ed25519_key and .pub into the root filesystem.

    Options:
      --image IMAGE                Path to the source .img or .img.zst
      --host-privkey KEY           Path to the ssh_host_ed25519 private key
      --expected-host-pubkey KEY   Expected public recipient key (validation only)
      -o, --output OUTPUT          Path to the personalized raw .img output
      -f, --force                  Overwrite OUTPUT if it already exists
      -h, --help                   Show this help
    EOF
    }

    die() {
      printf 'extract-image: %s\n' "$*" >&2
      exit 1
    }

    normalize_pubkey() {
      awk 'NF >= 2 { print $1 " " $2 }'
    }

    extract_comment() {
      awk 'NF >= 3 { $1 = ""; $2 = ""; sub(/^  */, ""); print }'
    }

    imagePath=
    hostPrivkey=
    outputPath=
    expectedHostPubkey=
    force=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --image)
          imagePath=$2
          shift 2
          ;;
        --host-privkey)
          hostPrivkey=$2
          shift 2
          ;;
        --expected-host-pubkey)
          expectedHostPubkey=$2
          shift 2
          ;;
        -o|--output)
          outputPath=$2
          shift 2
          ;;
        -f|--force)
          force=1
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage >&2
          die "unknown argument: $1"
          ;;
      esac
    done

    [[ -n "$imagePath" ]] || die "--image is required"
    [[ -n "$hostPrivkey" ]] || die "--host-privkey is required"
    [[ -n "$outputPath" ]] || die "--output is required"

    imagePath=$(realpath "$imagePath")
    hostPrivkey=$(realpath "$hostPrivkey")
    outputPath=$(realpath -m "$outputPath")

    [[ -r "$imagePath" ]] || die "image is not readable: $imagePath"
    [[ -r "$hostPrivkey" ]] || die "host private key is not readable: $hostPrivkey"

    if [[ -e "$outputPath" && "$force" -ne 1 ]]; then
      die "output already exists: $outputPath (use --force to overwrite)"
    fi

    generatedPubkey=$(${openssh}/bin/ssh-keygen -y -f "$hostPrivkey" 2>/dev/null | normalize_pubkey)
    [[ -n "$generatedPubkey" ]] || die "failed to derive public key from $hostPrivkey"

    expectedPubkeyNormalized=
    expectedComment=
    if [[ -n "$expectedHostPubkey" ]]; then
      expectedPubkeyNormalized=$(printf '%s\n' "$expectedHostPubkey" | normalize_pubkey)
      expectedComment=$(printf '%s\n' "$expectedHostPubkey" | extract_comment || true)
      if [[ "$generatedPubkey" != "$expectedPubkeyNormalized" ]]; then
        die "host private key does not match the expected host recipient pubkey"
      fi
    fi

    tmpDir=$(mktemp -d)
    trap 'rm -rf "$tmpDir"' EXIT

    injectedPrivkey="$tmpDir/ssh_host_ed25519_key"
    generatedPubkeyFile="$tmpDir/ssh_host_ed25519_key.pub"
    cp --reflink=auto -- "$hostPrivkey" "$injectedPrivkey"
    if [[ -n "$expectedComment" ]]; then
      printf '%s %s\n' "$generatedPubkey" "$expectedComment" > "$generatedPubkeyFile"
    else
      printf '%s\n' "$generatedPubkey" > "$generatedPubkeyFile"
    fi

    mkdir -p "$(dirname "$outputPath")"
    rm -f "$outputPath"

    case "$imagePath" in
      *.zst)
        zstd -d --stdout -- "$imagePath" > "$outputPath"
        ;;
      *)
        cp --reflink=auto -- "$imagePath" "$outputPath"
        ;;
    esac
    chmod u+w "$outputPath"

    rootPartition=$(printf 'run\nlist-filesystems\n' | guestfish --ro -a "$outputPath" | awk -F': ' '$2 == "ext4" { print $1; exit }')
    [[ -n "$rootPartition" ]] || die "failed to find an ext4 root filesystem in $outputPath"

    printf '%s\n' \
      "run" \
      "mount $rootPartition /" \
      "mkdir-p /etc/ssh" \
      "upload $injectedPrivkey /etc/ssh/ssh_host_ed25519_key" \
      "chmod 0600 /etc/ssh/ssh_host_ed25519_key" \
      "upload $generatedPubkeyFile /etc/ssh/ssh_host_ed25519_key.pub" \
      "chmod 0644 /etc/ssh/ssh_host_ed25519_key.pub" \
      "sync" \
      | guestfish --rw -a "$outputPath"

    installedPubkey=$(printf '%s\n' "run" "mount $rootPartition /" "cat /etc/ssh/ssh_host_ed25519_key.pub" | guestfish --ro -a "$outputPath" | normalize_pubkey)

    if [[ "$installedPubkey" != "$generatedPubkey" ]]; then
      die "verification failed after injecting SSH host key"
    fi

    printf 'Personalized image written to %s\n' "$outputPath"
  '';

  derivationArgs = {
    meta = {
      description = "Offline SD image extractor and SSH host-key injector";
      mainProgram = "extract-image";
      platforms = [ "x86_64-linux" ];
    };
  };
}
