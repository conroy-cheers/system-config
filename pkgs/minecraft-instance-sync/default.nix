{ pkgs }:

let
  python = pkgs.python3.withPackages (ps: [ ps.nbtlib ]);
in
pkgs.writeShellApplication {
  name = "minecraft-instance-sync";
  runtimeInputs = [ python ];
  text = ''
    exec python - "$@" <<'PY'
    import argparse
    import json
    from pathlib import Path

    import nbtlib
    from nbtlib import Compound, File, List, String


    def ensure_server(instance_dir: Path, server_name: str, server_address: str) -> None:
        servers_path = instance_dir / "servers.dat"
        if servers_path.exists():
            data = nbtlib.load(servers_path)
        else:
            data = File({"servers": List[Compound]()})

        servers = data.get("servers")
        if not isinstance(servers, List):
            servers = List[Compound]()

        for server in servers:
            current_name = str(server.get("name", ""))
            current_ip = str(server.get("ip", ""))
            if current_name == server_name or current_ip == server_address:
                server["name"] = String(server_name)
                server["ip"] = String(server_address)
                break
        else:
            servers.append(
                Compound(
                    {
                        "name": String(server_name),
                        "ip": String(server_address),
                    }
                )
            )

        data["servers"] = servers
        instance_dir.mkdir(parents=True, exist_ok=True)
        data.save(servers_path)


    def parse_string_list(raw: str | None, default: list[str]) -> list[str]:
        if raw is None or raw == "":
            return list(default)

        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return list(default)

        if isinstance(value, list) and all(isinstance(item, str) for item in value):
            return value

        return list(default)


    def ensure_resource_pack(instance_dir: Path, resource_pack_name: str | None) -> None:
        if not resource_pack_name:
            return

        options_path = instance_dir / "options.txt"
        ordered_keys: list[str] = []
        values: dict[str, str] = {}

        if options_path.exists():
            for raw_line in options_path.read_text().splitlines():
                key, sep, value = raw_line.partition(":")
                if sep == "":
                    key = raw_line
                    value = ""
                ordered_keys.append(key)
                values[key] = value

        pack_entry = f"file/{resource_pack_name}"
        resource_packs = parse_string_list(values.get("resourcePacks"), ["vanilla"])
        if "vanilla" not in resource_packs:
            resource_packs.insert(0, "vanilla")
        if pack_entry not in resource_packs:
            resource_packs.append(pack_entry)

        incompatible_resource_packs = parse_string_list(
            values.get("incompatibleResourcePacks"),
            [],
        )
        if pack_entry not in incompatible_resource_packs:
            incompatible_resource_packs.append(pack_entry)

        values["resourcePacks"] = json.dumps(resource_packs, separators=(",", ":"))
        values["incompatibleResourcePacks"] = json.dumps(
            incompatible_resource_packs,
            separators=(",", ":"),
        )

        for key in ["resourcePacks", "incompatibleResourcePacks"]:
            if key not in ordered_keys:
                ordered_keys.append(key)

        seen = set()
        lines = []
        for key in ordered_keys:
            if key in seen or key not in values:
                continue
            seen.add(key)
            lines.append(f"{key}:{values[key]}")

        instance_dir.mkdir(parents=True, exist_ok=True)
        options_path.write_text("\n".join(lines) + "\n")


    def main() -> None:
        parser = argparse.ArgumentParser()
        parser.add_argument("--instance-dir", required=True)
        parser.add_argument("--server-name", required=True)
        parser.add_argument("--server-address", required=True)
        parser.add_argument("--resource-pack")
        args = parser.parse_args()

        instance_dir = Path(args.instance_dir)
        ensure_server(instance_dir, args.server_name, args.server_address)
        ensure_resource_pack(instance_dir, args.resource_pack)


    if __name__ == "__main__":
        main()
    PY
  '';
}
