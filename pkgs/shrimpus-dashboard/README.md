# Shrimpus dashboard

A fixed 296 × 152 black, white, and red dashboard for the three-colour e-paper
panel. The calendar answers “what day is it?”, the daily forecast gives the
low/high temperature and chance of rain, and the footer shows connectivity and
when the forecast was fetched. Temperatures are daily extremes, not live readings.

Red emphasizes the calendar and offline/stale states. There is no animation or
ticking clock. Network state is checked once a minute; forecasts refresh every
30 minutes, at midnight, or once a minute after a failure. The window updates only
when its snapshot changes.

## Build and preview

From the flake root, on macOS:

```sh
nix run .#shrimpus-dashboard -- --preview
```

The preview uses deterministic sample data, not live weather or NetworkManager.
For a 1:1 physical-pixel preview on a Retina display, prefix the command with
`SLINT_SCALE_FACTOR=1`. The Linux build uses KMS directly.

To produce a display-sized image without opening a window:

```sh
nix run .#shrimpus-dashboard -- --render-preview /tmp/shrimpus.ppm
```

This uses Slint's software renderer, then the same RGB-to-black/white/red
conversion as the SSD16xx driver. It does not simulate the physical pigment,
refresh waveform, or ghosting. PPM can be converted to PNG with `sips` on macOS:

```sh
sips -s format png /tmp/shrimpus.ppm --out /tmp/shrimpus.png
```

Set `SHRIMPUS_PREVIEW_CASE` to `normal`, `offline`, `missing`, `long`, `sun`,
`cloud`, `fog`, `rain`, `snow`, `storm`, or `unknown` with either preview command.
The `long` case exercises a long SSID, a two-digit date, negative temperatures,
100% rain, and the longest condition label.

For local Cargo builds, copy `DejaVuSansMono.ttf`,
`DejaVuSansCondensed-Bold.ttf`, and `MaterialSymbolsOutlined.ttf` into `ui/` first;
Nix supplies these automatically from `dejavu_fonts` and `material-symbols`.
They are intentionally ignored by Git. Distinct font families preserve regular
captions and bold primary text with Slint 1.18's static font embedding.

## Freshness and offline behavior

`Updated HH:MM` is the last successful fetch time. If a subsequent fetch fails,
today's forecast remains visible with a red `Saved HH:MM` label. Cached forecasts
from another day, future timestamps, and legacy caches without a fetch timestamp
are discarded. With no usable forecast, the display shows `No forecast` and
`Update pending`, never placeholder weather values. The normal network footer
shows the SSID; disconnection shows a crossed Wi-Fi icon and `Offline`.

The date and update times use the system timezone, which should match
`SHRIMPUS_WEATHER_TIMEZONE` (default `Australia/Melbourne`). Coordinates are set
with `SHRIMPUS_WEATHER_LATITUDE` and `SHRIMPUS_WEATHER_LONGITUDE`; the default is
Melbourne. `SHRIMPUS_WEATHER_CACHE` overrides the cache path.

Material Symbols glyphs are embedded at their rendered sizes at build time,
including 2× sizes for Retina previews. No SVGs or font binaries are vendored.
The installed package retains one DejaVu face because Slint initializes its
font fallback collection before registering the embedded glyph atlas. The
service points fontconfig only at that face and keeps its cache private.
Font attribution and the Apache 2.0 license are in [ui/icons](ui/icons/README.md)
and included in the Nix package.

Run the data/cache checks with `cargo test --release` or build the Nix package,
which also runs them.
