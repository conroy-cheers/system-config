{
  dejavu_fonts,
  fontconfig,
  lib,
  material-symbols,
  pkg-config,
  rustPlatform,
  stdenv,
  udev,
}:

rustPlatform.buildRustPackage {
  pname = "shrimpus-dashboard";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  cargoHash = "sha256-R06pm675moCSfNJ0Kx8jYU411u7ZVOpEfnuS9aETSCU=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    fontconfig
    udev
  ];

  postPatch = ''
    cp ${dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
      ui/DejaVuSansMono.ttf
    cp ${dejavu_fonts}/share/fonts/truetype/DejaVuSansCondensed-Bold.ttf \
      ui/DejaVuSansCondensed-Bold.ttf
    cp '${material-symbols}/share/fonts/truetype/MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf' \
      ui/MaterialSymbolsOutlined.ttf
  '';

  doCheck = true;

  postInstall = ''
    # Slint initializes font discovery before registering the embedded glyph
    # atlas, so retain one small fallback instead of a system font collection.
    install -Dm644 ui/DejaVuSansMono.ttf \
      $out/share/fonts/truetype/DejaVuSansMono.ttf
    install -Dm644 ui/icons/LICENSE \
      $out/share/licenses/shrimpus-dashboard/material-symbols-LICENSE
    install -Dm644 ui/icons/README.md \
      $out/share/licenses/shrimpus-dashboard/material-symbols-NOTICE.md
  '';

  meta = {
    description = "Date, Wi-Fi, and weather dashboard for shrimpus";
    license = [
      dejavu_fonts.meta.license
      lib.licenses.mit
      lib.licenses.asl20
    ];
    mainProgram = "shrimpus-dashboard";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
    ];
  };
}
