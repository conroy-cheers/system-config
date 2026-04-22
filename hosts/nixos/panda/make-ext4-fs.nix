{
  pkgs,
  lib,
  storePaths,
  compressImage ? false,
  zstd,
  populateImageCommands ? "",
  volumeLabel,
  uuid ? "44444444-4444-4444-8888-888888888888",
  e2fsprogs,
  libfaketime,
  perl,
  fakeroot,
  extraPaddingMiB ? 12288,
}:

let
  sdClosureInfo = pkgs.buildPackages.closureInfo { rootPaths = storePaths; };
in
pkgs.stdenv.mkDerivation {
  name = "ext4-fs.img${lib.optionalString compressImage ".zst"}";

  nativeBuildInputs = [
    e2fsprogs.bin
    libfaketime
    perl
    fakeroot
  ]
  ++ lib.optional compressImage zstd;

  buildCommand = ''
    scratchRoot=$(mktemp -d /build-info/ext4-fs.XXXXXX)
    rootImageDir="$scratchRoot/rootImage"
    trap 'chmod -R u+w "$scratchRoot" 2>/dev/null || true; rm -rf "$scratchRoot" 2>/dev/null || true' EXIT
    mkdir -p ./files "$rootImageDir/nix/store"

    img="$scratchRoot/rootfs.img"
    ${populateImageCommands}

    echo "Preparing store paths for image..."

    xargs -I % cp -dR --reflink=auto --no-preserve=ownership % -t "$rootImageDir/nix/store/" < ${sdClosureInfo}/store-paths
    (
      GLOBIGNORE=".:.."
      shopt -u dotglob

      for f in ./files/*; do
          cp -dR --reflink=auto --no-preserve=ownership -t "$rootImageDir/" "$f"
      done
    )

    cp ${sdClosureInfo}/registration "$rootImageDir/nix-path-registration"

    numInodes=$(find "$rootImageDir" | wc -l)
    numDataBlocks=$(du -s -c -B 4096 --apparent-size "$rootImageDir" | tail -1 | awk '{ print int($1 * 1.20) }')
    bytes=$((2 * 4096 * $numInodes + 4096 * $numDataBlocks))
    bytes=$((bytes + ${toString extraPaddingMiB} * 1024 * 1024))
    echo "Creating an EXT4 image of $bytes bytes (numInodes=$numInodes, numDataBlocks=$numDataBlocks, extraPaddingMiB=${toString extraPaddingMiB})"

    mebibyte=$(( 1024 * 1024 ))
    if (( bytes % mebibyte )); then
      bytes=$(( ( bytes / mebibyte + 1) * mebibyte ))
    fi

    truncate -s $bytes $img

    faketime -f "1970-01-01 00:00:01" fakeroot mkfs.ext4 -L ${volumeLabel} -U ${uuid} -d "$rootImageDir" $img

    export EXT2FS_NO_MTAB_OK=yes
    if ! fsck.ext4 -n -f $img; then
      echo "--- Fsck failed for EXT4 image of $bytes bytes (numInodes=$numInodes, numDataBlocks=$numDataBlocks) ---"
      cat errorlog
      return 1
    fi

    resize2fs -M $img

    new_size=$(dumpe2fs -h $img | awk -F: \
      '/Block count/{count=$2} /Block size/{size=$2} END{print (count*size+16*2**20)/size}')

    resize2fs $img $new_size

    if [ ${toString compressImage} ]; then
      echo "Compressing image"
      zstd -T$NIX_BUILD_CORES -v --no-progress "$img" -o "$out"
    else
      cp "$img" "$out"
    fi
  '';
}
