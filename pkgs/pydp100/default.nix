{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}:
let
  python = python3.withPackages (ps: [
    ps.hid
    ps.crcmod
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "pydp100";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python ];
  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    python -m unittest -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 dp100.py $out/libexec/pydp100/dp100.py
    install -Dm644 config.txt $out/share/pydp100/config.txt

    for action in read off up; do
      makeWrapper ${python}/bin/python $out/bin/dp100-power$action \
        --add-flags "$out/libexec/pydp100/dp100.py $action"
    done

    runHook postInstall
  '';

  meta = {
    description = "Control and monitor an Alientek DP100 power supply";
    platforms = lib.platforms.unix;
  };
}
