# AutoEq

`nix run .#autoeq -- --help` runs the packaged AutoEq CLI. The package is
also a Python module, usable with `python3.withPackages`.

The package exposes the upstream numerical datasets through
`pkgs.autoeq.measurements` and `pkgs.autoeq.targets`. These paths retain the
upstream directory structure and filenames. They come from a separately pinned
`pkgs.autoeq.data` derivation, since the Python distribution excludes them.
Only measurement data and targets are fetched; precomputed results, plots and
raw captures are omitted. Using the CLI alone does not require the data.

The repository's extended `lib` provides `mkAutoEq`, which builds a single
Equalizer APO text file or convolution impulse-response WAV:

```nix
lib.mkAutoEq pkgs {
  name = "headphones-eq";
  measurement = "${pkgs.autoeq.measurements}/oratory1990/data/over-ear/HIFIMAN Ananda Stealth.csv";
  target = "${pkgs.autoeq.targets}/Harman over-ear 2018 without bass.csv";
  format = "parametric";
  parametricEqConfig = "8_PEAKING_WITH_SHELVES";
  parameters = {
    fs = 48000;
    bass-boost = 6;
    max-gain = 6;
    tilt = -0.2;
  };
}
```

`measurement` and `target` also accept local paths or fetched derivations. Pin
custom remote data by revision and hash. `parameters` uses AutoEq's CLI option
names without the leading `--`; values are shell escaped. Boolean `true` enables a flag,
`false` omits it, and comma-separated options use strings. Input, target, output
paths and the selected format's flag are managed by the helper. The defaults
are 48 kHz and one worker; other processing defaults come from AutoEq.

`format` accepts `parametric`, `graphic`, `fixed-band`, or `convolution`.
`parametricEqConfig`
accepts an upstream preset name (including comma-separated names), a YAML file
path, or a Nix attribute set/list describing the upstream filter configuration.
Attribute sets/lists are serialized as JSON, which AutoEq reads as YAML. For
fixed-band output, set `parameters.fixed-band-eq-config` to an upstream preset
or YAML file. Use convergence-based optimizer settings rather than `max_time`
or `min_change_rate` to avoid machine-speed-dependent results.

For convolution, select a single sample rate and either minimum or linear
phase. The defaults are minimum phase and 32-bit PCM; the WAV already includes
AutoEq's gain normalization/headroom, so no separate preamp is needed:

```nix
lib.mkAutoEq pkgs {
  name = "headphones-ir";
  measurement = "${pkgs.autoeq.measurements}/oratory1990/data/over-ear/HIFIMAN Ananda Stealth.csv";
  target = "${pkgs.autoeq.targets}/Harman over-ear 2018 without bass.csv";
  format = "convolution";
  parameters = {
    fs = 48000;
    phase = "minimum";
    bit-depth = 32;
    f-res = 10;
    bass-boost = 6;
  };
}
```

`parameters.fs` must be a single positive integer (or integer string) for
convolution, and `parameters.phase` must be `minimum` or `linear`. Build separate
derivations for multiple sample rates/phases. Smaller `f-res` values produce
longer impulse responses with finer frequency resolution. Linear phase adds
a fixed delay and pre-ringing; minimum phase avoids that fixed linear-phase
delay, although the convolver still requires processing time/buffering.

The MOTU configuration uses oratory1990's HIFIMAN Ananda Stealth measurement,
Harman over-ear 2018 without bass plus an 18 dB bass shelf at 80 Hz (Q 0.7),
a 24 dB maximum correction gain, and a minimum-phase convolution filter.
It generates WAVs for the default and allowed clock rates
declared in `services.pipewire.extraConfig.pipewire`, applying clock properties
in fragment filename order. PipeWire's convolver selects the nearest-rate WAV
and resamples if the live graph uses another rate. Runtime overrides do not
trigger Nix builds. Stereo channels are convolved independently; the existing
`motu-eq` toggle controls the whole correction. No low-cut filter is applied.

Convolution follows AutoEq's smoothed correction curve without the previous
11-filter fit, but does not improve the underlying headphone measurement or
guarantee a better subjective result.

AutoEq 4.1.2 declares older Python and scientific-library version constraints.
The Nix package relaxes these to use the locked nixpkgs stack. Its import check
and actual profile builds validate the paths used here; other AutoEq modes may
need additional compatibility work when updating dependencies.
