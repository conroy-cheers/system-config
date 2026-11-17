{ lib, pkgs }:
let
  # Home Manager's merger deliberately refuses store-backed symlinks. Migrate
  # files created by earlier versions of this module before handing them to it.
  migrate = target: ''
    if [[ ! -v DRY_RUN && -L ${lib.escapeShellArg target} ]]; then
      (
        set -e
        target=${lib.escapeShellArg target}
        case "$(${lib.getExe' pkgs.coreutils "readlink"} -f -- "$target")" in
          ${builtins.storeDir}/*)
            ${lib.getExe pkgs.jaq} --from toml '.' "$target" > /dev/null
            temporary="$(${lib.getExe' pkgs.coreutils "mktemp"} "$target.migrate.XXXXXX")"
            trap 'rm -f -- "$temporary"' EXIT
            ${lib.getExe' pkgs.coreutils "install"} -m 600 -- "$target" "$temporary"
            ${lib.getExe' pkgs.coreutils "mv"} -fT -- "$temporary" "$target"
            ;;
        esac
      )
    fi
  '';
in
{
  inherit migrate;
  merge =
    {
      source,
      target,
      removeSettings ? [ ],
    }:
    migrate target
    + lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "toml";
      empty = "{}";
      path = target;
      staticSettings = source;
      mode = "600";
      # A changed MCP transport must discard fields from the previous transport.
      # This is the same normalization used by Home Manager's Codex module.
      jqOperation = ''
        ($dynamic * $static) | delpaths(${builtins.toJSON removeSettings})
        | reduce (($static.mcp_servers // {}) | to_entries[]) as $server (.;
            if $server.value | has("url") then
              .mcp_servers[$server.key] |= del(.command, .args, .env, .env_vars, .cwd)
            elif $server.value | has("command") then
              .mcp_servers[$server.key] |= del(.url, .bearer_token, .bearer_token_env_var,
                .http_headers, .env_http_headers, .http_headers_helper, .oauth, .oauth_resource, .auth)
            else . end)
      '';
    };
}
