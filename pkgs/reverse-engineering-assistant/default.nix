{
  fetchPypi,
  fetchurl,
  ghidra,
  jdk21,
  lib,
  lndir,
  makeWrapper,
  python3Packages,
  runCommand,
  unzip,
}:
let
  version = "7.3.0";

  pyghidra = python3Packages.buildPythonPackage rec {
    pname = "pyghidra";
    version = "3.1.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-IQasEx65pJkKee6E3C05p5LPey0N5eqvGw5tfS0pC7Y=";
    };

    build-system = with python3Packages; [
      setuptools
      wheel
    ];

    dependencies = with python3Packages; [
      jpype1
      packaging
    ];

    doCheck = false;

    pythonRelaxDeps = [
      "jpype1"
    ];

    pythonImportsCheck = [
      "pyghidra"
    ];
  };

  revaGhidraExtension = fetchurl {
    url = "https://github.com/cyberkaida/reverse-engineering-assistant/releases/download/v${version}/ghidra_12.0.4_PUBLIC_20260613_reverse-engineering-assistant.zip";
    hash = "sha256-zHYMyYE4lLrgizEyFDSg7P4MbpBWbAwvxipm57Yr6PU=";
  };

  ghidra-with-reva =
    runCommand "ghidra-with-reva-${ghidra.version}"
      {
        nativeBuildInputs = [
          lndir
          unzip
        ];
      }
      ''
        mkdir -p "$out"
        lndir -silent ${ghidra} "$out"
        mkdir -p "$out/lib/ghidra/Ghidra/Extensions"
        unzip -q ${revaGhidraExtension} -d "$out/lib/ghidra/Ghidra/Extensions"
      '';
in
python3Packages.buildPythonApplication {
  pname = "reverse-engineering-assistant";
  inherit version;
  format = "wheel";

  src = fetchurl {
    url = "https://github.com/cyberkaida/reverse-engineering-assistant/releases/download/v${version}/reverse_engineering_assistant-${version}-py3-none-any.whl";
    hash = "sha256-4j1QLYIbj6fs/espiHxBwsYKpMbbUcu1DU5kYHP+QqM=";
  };

  dependencies = with python3Packages; [
    httpx
    httpx-sse
    mcp
    pyghidra
  ];

  nativeBuildInputs = [
    makeWrapper
  ];

  postInstall = ''
    reva_launcher="$out/${python3Packages.python.sitePackages}/reva_cli/launcher.py"

    substituteInPlace "$out/${python3Packages.python.sitePackages}/reva_cli/__main__.py" \
      --replace-fail \
        '        pyghidra.start(verbose=args.verbose)' \
        $'        launcher = pyghidra.HeadlessPyGhidraLauncher(verbose=args.verbose)\n        for jar in Path("${ghidra-with-reva}/lib/ghidra/Ghidra/Extensions/reverse-engineering-assistant/lib").glob("*.jar"):\n            launcher.add_class_files(str(jar))\n        launcher.start()'

    substituteInPlace "$reva_launcher" \
      --replace-fail \
        '            from reva.headless import RevaHeadlessLauncher' \
        $'            from jpype import imports\n            imports.registerDomain("reva")\n            from reva.headless import RevaHeadlessLauncher'

    wrapProgram "$out/bin/mcp-reva" \
      --set JAVA_HOME ${jdk21.home} \
      --prefix PATH : ${lib.makeBinPath [ jdk21 ]} \
      --set-default GHIDRA_INSTALL_DIR ${ghidra-with-reva}/lib/ghidra
  '';

  doCheck = false;

  pythonImportsCheck = [
    "reva_cli"
  ];

  meta = {
    description = "AI-powered reverse engineering assistant for Ghidra with an MCP server";
    homepage = "https://github.com/cyberkaida/reverse-engineering-assistant";
    license = lib.licenses.asl20;
    mainProgram = "mcp-reva";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
