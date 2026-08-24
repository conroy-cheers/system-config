{
  lib,
  python3Packages,
  runCommand,
  writers,
}:

let
  testPython = python3Packages.python.withPackages (pythonPackages: [
    pythonPackages.fastmcp
    pythonPackages.httpx
  ]);
in
writers.writePython3Bin "icloud-mail-mcp-gateway" {
  libraries = [
    python3Packages.fastmcp
    python3Packages.httpx
  ];
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./gateway.py)
// {
  passthru.tests.unit =
    runCommand "icloud-mail-mcp-gateway-unit-tests"
      {
        nativeBuildInputs = [ testPython ];
      }
      ''
        cp -r ${./.} source
        chmod -R u+w source
        python -m unittest discover -s source/tests -v
        touch $out
      '';

  meta = {
    description = "Authenticated Streamable HTTP gateway for a stdio mail MCP server";
    license = lib.licenses.mit;
    mainProgram = "icloud-mail-mcp-gateway";
  };
}
