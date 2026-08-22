{
  fetchPypi,
  lib,
  notmuch,
  python313Packages,
}:

let
  inherit (python313Packages)
    anyio
    buildPythonApplication
    buildPythonPackage
    h11
    html2text
    idna
    jsonschema
    opentelemetry-api
    pydantic
    pydantic-settings
    pyjwt
    pytestCheckHook
    python-multipart
    sse-starlette
    starlette
    truststore
    typing-extensions
    typing-inspection
    uvicorn
    ;

  mcp-types = buildPythonPackage {
    pname = "mcp-types";
    version = "2.0.0b2";
    format = "wheel";

    src = fetchPypi {
      pname = "mcp_types";
      version = "2.0.0b2";
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-NcnDOruQp33GrR2uyqZAfHiMLzLRTVLa2PhDxPAI6uI=";
    };

    dependencies = [
      pydantic
      typing-extensions
    ];

    pythonImportsCheck = [ "mcp_types" ];
  };

  httpcore2 = buildPythonPackage {
    pname = "httpcore2";
    version = "2.5.0";
    format = "wheel";

    src = fetchPypi {
      pname = "httpcore2";
      version = "2.5.0";
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-XONRiN5GHTHo0AC/uO+L8ixsFlh6IR5Vcd6qXpvfhCo=";
    };

    dependencies = [
      h11
      truststore
    ];

    pythonImportsCheck = [ "httpcore2" ];
  };

  httpx2 = buildPythonPackage {
    pname = "httpx2";
    version = "2.5.0";
    format = "wheel";

    src = fetchPypi {
      pname = "httpx2";
      version = "2.5.0";
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-PS1NnPS2HxofRqlZR8/bR+gMtWovkcYlasj1jkiR30E=";
    };

    dependencies = [
      anyio
      httpcore2
      idna
      truststore
    ];

    pythonImportsCheck = [ "httpx2" ];
  };

  mcp = buildPythonPackage {
    pname = "mcp";
    version = "2.0.0b2";
    format = "wheel";

    src = fetchPypi {
      pname = "mcp";
      version = "2.0.0b2";
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-nFCuWvoIlgq3bVCqOtqzGElS2b6n74f0pKW6aL3vzwo=";
    };

    dependencies = [
      anyio
      httpx2
      jsonschema
      mcp-types
      opentelemetry-api
      pydantic
      pydantic-settings
      pyjwt
      python-multipart
      sse-starlette
      starlette
      typing-extensions
      typing-inspection
      uvicorn
    ];

    pythonImportsCheck = [ "mcp" ];
  };
in
buildPythonApplication {
  pname = "mcp-server-notmuch";
  version = "3.0.0";
  pyproject = true;

  src = fetchPypi {
    pname = "mcp_server_notmuch";
    version = "3.0.0";
    hash = "sha256-Z3XadIjWjKM5Kfv3VV3KLMTSSXAUttz9NoEAWv5krBI=";
  };

  # The protocol tests deliberately spawn a second Python process. The MCP
  # SDK's default subprocess environment omits PYTHONPATH, which hides Nix's
  # check-time dependencies from that child, so preserve the test environment.
  postPatch = ''
    substituteInPlace mcpnotmuch/__init__.py \
      --replace-fail '__version__ = "0.1.0"' '__version__ = "3.0.0"'
    substituteInPlace tests/conftest.py \
      --replace-fail \
        "params = StdioServerParameters(command=sys.executable, args=args)" \
        "params = StdioServerParameters(command=sys.executable, args=args, env=os.environ.copy())"
  '';

  build-system = [ python313Packages.hatchling ];

  dependencies = [
    html2text
    mcp
  ];

  nativeCheckInputs = [
    notmuch
    pytestCheckHook
  ];

  pythonImportsCheck = [ "mcpnotmuch" ];

  meta = {
    description = "Read-first MCP server for a local notmuch mail database";
    homepage = "https://github.com/hgn/mcp-server-notmuch";
    license = lib.licenses.mit;
    mainProgram = "mcp-server-notmuch";
  };
}
