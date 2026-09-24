"""Offline NIXOS_SD image personalization, using native debugfs on macOS/Linux."""

import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs).stdout


def normalized_key(data):
    fields = data.split()
    if len(fields) < 2 or fields[0] != b"ssh-ed25519":
        raise ValueError("expected an Ed25519 SSH host key")
    return b" ".join(fields[:2])


def root_partition(image):
    """Require one Linux primary partition, bounded and nonoverlapping."""
    size = image.stat().st_size
    with image.open("rb") as stream:
        mbr = stream.read(512)
        if len(mbr) != 512 or mbr[510:] != b"\x55\xaa":
            raise ValueError("expected an MBR disk image")
        partitions = []
        for index in range(4):
            entry = mbr[446 + index * 16 : 462 + index * 16]
            kind = entry[4]
            start, sectors = struct.unpack_from("<II", entry, 8)
            if kind == 0:
                continue
            offset, length = start * 512, sectors * 512
            if offset < 512 or not length or offset + length > size:
                raise ValueError("partition lies outside the image")
            partitions.append((offset, length, kind))
        ordered = sorted(partitions)
        for left, right in zip(ordered, ordered[1:]):
            if left[0] + left[1] > right[0]:
                raise ValueError("overlapping partitions")
        roots = [p for p in partitions if p[2] == 0x83]
        if len(roots) != 1:
            raise ValueError("expected exactly one Linux root partition")
        offset, length, _ = roots[0]
        stream.seek(offset + 1024)
        superblock = stream.read(1024)
        if (superblock[56:58] != b"\x53\xef"
                or superblock[120:136].rstrip(b"\0") != b"NIXOS_SD"):
            raise ValueError("root partition must be an ext filesystem labeled NIXOS_SD")
    return offset, length


def copy_range(source, target, length):
    while length:
        chunk = source.read(min(length, 1024 * 1024))
        if not chunk:
            raise ValueError("unexpected end of image")
        target.write(chunk)
        length -= len(chunk)


def personalize(args):
    image = args.image.resolve(strict=True)
    key = args.host_privkey.resolve(strict=True)
    output = args.output.absolute()
    if output.resolve() in (image, key):
        raise ValueError("output must differ from the image and private key")
    if output.exists() and not args.force:
        raise ValueError("output already exists (use --force to replace it)")
    expected = normalized_key(args.expected_host_pubkey.encode())
    public = normalized_key(run("ssh-keygen", "-y", "-P", "", "-f", str(key)))
    if public != expected:
        raise ValueError("private key does not match the expected host recipient")

    output.parent.mkdir(parents=True, exist_ok=True)
    # Keep private material and incomplete images outside Git/the Nix store.
    # TemporaryDirectory is 0700; umask also protects the final raw image.
    with tempfile.TemporaryDirectory(prefix=".personalize-", dir=output.parent) as temp:
        work = Path(temp)
        raw = work / "disk.img"
        with raw.open("wb") as target:
            if image.suffix == ".zst":
                subprocess.run(["zstd", "-q", "-d", "-c", str(image)],
                               stdout=target, check=True)
            else:
                with image.open("rb") as source:
                    shutil.copyfileobj(source, target, 1024 * 1024)
        offset, length = root_partition(raw)
        root = work / "root.img"
        with raw.open("rb") as source, root.open("wb") as target:
            source.seek(offset)
            copy_range(source, target, length)
        run("e2fsck", "-f", "-n", str(root))

        def debug(command, write=False):
            # Commands contain only fixed filenames, never user-controlled paths.
            return run("debugfs", *(["-w"] if write else []), "-R", command,
                       "root.img", cwd=work).decode()

        for directory in ("/etc", "/etc/ssh"):
            info = debug(f"stat {directory}")
            if not info.strip():
                debug(f"mkdir {directory}", write=True)
                info = debug(f"stat {directory}")
            if "Type: directory" not in info:
                raise ValueError(f"{directory} must be a real directory")

        (work / "host-key").write_bytes(key.read_bytes())
        (work / "host-key.pub").write_bytes(public + b"\n")
        for source, target, mode in (
            ("host-key", "/etc/ssh/ssh_host_ed25519_key", "0100600"),
            ("host-key.pub", "/etc/ssh/ssh_host_ed25519_key.pub", "0100644"),
        ):
            info = debug(f"stat {target}")
            if info.strip():
                if "Type: regular" not in info:
                    raise ValueError(f"refusing to replace non-regular {target}")
                debug(f"rm {target}", write=True)
            debug(f"write {source} {target}", write=True)
            for field, value in (("mode", mode), ("uid", "0"), ("gid", "0")):
                debug(f"set_inode_field {target} {field} {value}", write=True)
            debug(f"dump {target} verified")
            if (work / "verified").read_bytes() != (work / source).read_bytes():
                raise ValueError("host key read-back verification failed")
            (work / "verified").unlink()
            info = debug(f"stat {target}")
            if not re.search(r"Mode:\s+0" + mode[-3:] + r"\b", info):
                raise ValueError("host key permissions verification failed")
            if not re.search(r"User:\s+0\s+Group:\s+0\b", info):
                raise ValueError("host key ownership verification failed")

        # debugfs does not reliably return nonzero for failed commands; the
        # read-back, metadata checks and fsck above/below are intentional.
        run("e2fsck", "-f", "-n", str(root))
        with root.open("rb") as source, raw.open("r+b") as target:
            target.seek(offset)
            copy_range(source, target, length)
            target.flush()
            os.fsync(target.fileno())
        if args.force:
            os.replace(raw, output)
        else:
            os.link(raw, output)  # Atomic publication without clobbering a file.
        print(f"Verified personalized image: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--host-privkey", type=Path, required=True)
    parser.add_argument("--expected-host-pubkey", required=True)
    parser.add_argument("--output", "-o", type=Path, required=True)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        personalize(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Captured tool output may contain private material: never echo it.
        parser.exit(1, f"personalize-sd-image: {error}\n")


if __name__ == "__main__":
    main()
