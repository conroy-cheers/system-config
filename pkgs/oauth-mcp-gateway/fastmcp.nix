# FastMCP 3.x requires MCP 1.x; Nixpkgs now defaults to MCP 2.x.
# Share the compatible dependency between our MCP services, whose packages
# are evaluated in isolation from the system overlays.
{ python3Packages }:
python3Packages.fastmcp.override {
  fastmcp-slim = python3Packages.fastmcp-slim.override {
    mcp = python3Packages.mcp_1;
  };
}
