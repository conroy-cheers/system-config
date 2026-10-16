{
  plezy,
  mpv-unwrapped,
  makeWrapper,
  cmake,
  python3,
  writeShellScript,
}:

let
  configure = writeShellScript "configure-plezy-integrated-mpv" ''
    exec ${python3}/bin/python3 ${./configure.py}
  '';
in
# Keep Plezy's native controls and system libmpv. The Linux render API uses
# OpenGL; gpu-next/Vulkan and its exclusive picture options cannot run here.
(plezy.override { inherit mpv-unwrapped; }).overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./sdr-bt2390.patch ];
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    makeWrapper
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    native_build=build/linux/x64/release
    ${cmake}/bin/cmake -S linux -B "$native_build" -DPLEZY_BUILD_MPV_PLAYER_LIFECYCLE_TESTS=ON
    ${cmake}/bin/cmake --build "$native_build" --target mpv_player_hdr_output_test --parallel "$NIX_BUILD_CORES"
    ${cmake}/bin/ctest --test-dir "$native_build" --output-on-failure -R '^mpv_player_hdr_output_test$'
    runHook postCheck
  '';
  postFixup = (old.postFixup or "") + ''
    wrapProgram "$out/bin/plezy" --run ${configure}
  '';
})
