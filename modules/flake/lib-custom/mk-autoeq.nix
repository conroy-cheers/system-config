{ lib }:
pkgs:
{
  name ? "autoeq-${format}",
  measurement,
  target,
  format ? "parametric",
  parametricEqConfig ? "8_PEAKING_WITH_SHELVES",
  parameters ? { },
}:
let
  formats = {
    parametric = {
      flag.parametric-eq = true;
      suffix = "ParametricEQ";
    };
    graphic = {
      flag = { };
      suffix = "GraphicEQ";
    };
    fixed-band = {
      flag.fixed-band-eq = true;
      suffix = "FixedBandEQ";
    };
    convolution = {
      flag.convolution-eq = true;
    };
  };
  selected = formats.${format} or (throw "mkAutoEq: unsupported format '${format}'");
  convolution = format == "convolution";
  configFile =
    if
      (builtins.isAttrs parametricEqConfig && !lib.isDerivation parametricEqConfig)
      || builtins.isList parametricEqConfig
    then
      # JSON is also valid YAML, the format consumed by AutoEq.
      pkgs.writeText "autoeq-peq.json" (builtins.toJSON parametricEqConfig)
    else
      parametricEqConfig;
  args = {
    fs = 48000;
    thread-count = 1;
  }
  // lib.optionalAttrs convolution {
    phase = "minimum";
    bit-depth = 32;
  }
  // parameters
  // selected.flag
  // {
    inherit target;
    parametric-eq-config = configFile;
    input-file = "measurement.csv";
    output-dir = "results";
  };
  sampleRate = args.fs;
  phase = args.phase or "minimum";
  outputFile =
    if convolution then
      "measurement ${phase} phase ${toString sampleRate}Hz.wav"
    else
      "measurement ${selected.suffix}.txt";
in
assert lib.assertMsg (
  !convolution
  || (builtins.isInt sampleRate && sampleRate > 0)
  || (builtins.isString sampleRate && builtins.match "[1-9][0-9]*" sampleRate != null)
) "mkAutoEq: convolution output requires a single positive integer parameters.fs";
assert lib.assertMsg (
  !convolution
  || builtins.elem phase [
    "minimum"
    "linear"
  ]
) "mkAutoEq: convolution output requires parameters.phase = minimum or linear";
pkgs.runCommand "${name}.${if convolution then "wav" else "txt"}"
  {
    nativeBuildInputs = [ pkgs.autoeq ];
    # Keep numerical libraries single-threaded and plotting headless.
    OPENBLAS_NUM_THREADS = "1";
    OMP_NUM_THREADS = "1";
    MPLBACKEND = "Agg";
    passthru = {
      inherit
        measurement
        target
        format
        parametricEqConfig
        parameters
        sampleRate
        phase
        ;
    };
    meta.description = "AutoEq ${format} equalizer configuration";
  }
  ''
    export HOME="$TMPDIR"
    cp ${lib.escapeShellArg (toString measurement)} measurement.csv
    chmod u+w measurement.csv
    autoeq ${lib.cli.toCommandLineShellGNU { } args}
    cp ${lib.escapeShellArg "results/measurement/${outputFile}"} "$out"
    test -s "$out"
  ''
