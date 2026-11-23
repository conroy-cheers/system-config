{
  lib,
  fetchgit,
  fetchPypi,
  python3Packages,
}:
let
  # The PyPI distribution excludes these datasets. Fetch the numerical inputs
  # separately, without the repository's precomputed EQs, plots or raw captures.
  data = fetchgit {
    name = "autoeq-data-7ae0f56";
    url = "https://github.com/jaakkopasanen/AutoEq.git";
    rev = "7ae0f56d53074872b028649617a22bbb4232feb7";
    hash = "sha256-MWSwrUk4pFPuEI4CaM2ua+SyixxypZdyJn9innzVxYA=";
    fetchSubmodules = false;
    nonConeMode = true;
    sparseCheckout = [
      "/measurements/*/data/"
      "/targets/"
    ];
  };
in
python3Packages.buildPythonPackage rec {
  pname = "autoeq";
  version = "4.1.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-1AIqFRdJ5v4RjqkZoChPHWzQqcEUfJfJEisnGN3VDnk=";
  };

  build-system = [ python3Packages.hatchling ];
  dependencies = with python3Packages; [
    pillow
    matplotlib
    scipy
    numpy
    tabulate
    soundfile
    pyyaml
    tqdm
  ];

  # Upstream pins its 2023 environment. Use the Python/scientific stack from
  # our locked nixpkgs instead; profile generation exercises it at build time.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'requires-python = ">=3.8,<3.12"' 'requires-python = ">=3.8"'
  '';
  pythonRelaxDeps = [
    "Pillow"
    "matplotlib"
    "scipy"
    "numpy"
    "tabulate"
    "soundfile"
    "pyyaml"
    "tqdm"
  ];

  env.MPLBACKEND = "Agg";
  preBuild = ''
    export MPLCONFIGDIR="$TMPDIR/matplotlib"
  '';

  # Upstream exposes `python -m autoeq`, but has no console entry point.
  postInstall = ''
    mkdir -p "$out/bin"
    cat > "$out/bin/autoeq" <<'PY'
    #!${python3Packages.python.interpreter}
    import runpy
    if __name__ == "__main__":
        runpy.run_module("autoeq", run_name="__main__")
    PY
    chmod +x "$out/bin/autoeq"
  '';

  pythonImportsCheck = [ "autoeq.frequency_response" ];

  passthru = {
    inherit data;
    measurements = "${data}/measurements";
    targets = "${data}/targets";
  };

  meta = {
    description = "Generate headphone equalizer configurations from frequency response measurements";
    homepage = "https://github.com/jaakkopasanen/AutoEq";
    license = lib.licenses.mit;
    mainProgram = "autoeq";
    platforms = lib.platforms.unix;
  };
}
