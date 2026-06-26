{
  callPackage,
  coreutils,
  lib,
  slack-mcp-server ? callPackage ../slack-mcp-server { },
  writeShellScriptBin,
}:

writeShellScriptBin "codex-slack-mcp" ''
  set -euo pipefail

  token_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/slack-mcp"

  if [ -z "''${SLACK_MCP_XOXP_TOKEN:-}" ] && [ -r "$token_dir/xoxp-token" ]; then
    export SLACK_MCP_XOXP_TOKEN="$(${lib.getExe' coreutils "cat"} "$token_dir/xoxp-token")"
  fi

  if [ -z "''${SLACK_MCP_XOXB_TOKEN:-}" ] && [ -r "$token_dir/xoxb-token" ]; then
    export SLACK_MCP_XOXB_TOKEN="$(${lib.getExe' coreutils "cat"} "$token_dir/xoxb-token")"
  fi

  exec ${lib.getExe slack-mcp-server} "$@"
''
