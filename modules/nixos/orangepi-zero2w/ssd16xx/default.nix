{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation {
  pname = "panel-ssd16xx";
  version = "1-${kernel.version}";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Makefile
      ./panel-ssd16xx.c
    ];
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  enableParallelBuilding = true;

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(NIX_BUILD_TOP)/source"
    "INSTALL_MOD_PATH=$(out)"
  ];
  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];

  meta = {
    description = "DRM driver for the Waveshare 2.66-inch three-colour e-paper panel";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
