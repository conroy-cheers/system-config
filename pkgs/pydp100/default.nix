{
  python3Packages,
  fetchFromGitHub,
  bash,
  coreutils,
}:
let
  pythonPath = python3Packages.makePythonPath (
    with python3Packages;
    [
      hid
      crcmod
    ]
  );
in
python3Packages.buildPythonApplication {
  pname = "pydp100";
  version = "0-unstable-22-01-2024";

  format = "other";
  dontBuild = true;

  src = fetchFromGitHub {
    owner = "palzhj";
    repo = "pydp100";
    rev = "116d10c0e5b34a80c4dfd9087f1b10544a89cab8";
    hash = "sha256-MDlKEzLqNxYKDIT64zF3CPzCYxjOlzTiY58R2wiIkVc=";
  };

  dependencies = with python3Packages; [
    hid
    crcmod
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 powerup.py $out/libexec/pydp100/powerup.py
    install -Dm755 powerread.py $out/libexec/pydp100/powerread.py
    install -Dm755 poweroff.py $out/libexec/pydp100/poweroff.py

    install -Dm644 config.txt $out/share/pydp100/config.txt

    install -Dm755 ${./dp100-powerread.sh} $out/bin/dp100-powerread
    substituteInPlace $out/bin/dp100-powerread \
      --replace "@bash@" "${bash}/bin/bash" \
      --replace "@pythonpath@" "${pythonPath}" \
      --replace "@python@" "${python3Packages.python}/bin/python" \
      --replace "@script@" "$out/libexec/pydp100/powerread.py"

    install -Dm755 ${./dp100-poweroff.sh} $out/bin/dp100-poweroff
    substituteInPlace $out/bin/dp100-poweroff \
      --replace "@bash@" "${bash}/bin/bash" \
      --replace "@pythonpath@" "${pythonPath}" \
      --replace "@python@" "${python3Packages.python}/bin/python" \
      --replace "@script@" "$out/libexec/pydp100/poweroff.py"

    install -Dm755 ${./dp100-powerup.sh} $out/bin/dp100-powerup
    substituteInPlace $out/bin/dp100-powerup \
      --replace "@bash@" "${bash}/bin/bash" \
      --replace "@mktemp@" "${coreutils}/bin/mktemp" \
      --replace "@rm@" "${coreutils}/bin/rm" \
      --replace "@cp@" "${coreutils}/bin/cp" \
      --replace "@pythonpath@" "${pythonPath}" \
      --replace "@python@" "${python3Packages.python}/bin/python" \
      --replace "@script@" "$out/libexec/pydp100/powerup.py"

    runHook postInstall
  '';
}
