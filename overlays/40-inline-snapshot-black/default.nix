_: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _: python-prev:
      let
        # inline-snapshot 0.34.2's test environment pins Black 25.1.0.
        # Newer Black releases reformat its documentation fixtures differently.
        black_25_1 = python-prev.black.overridePythonAttrs (_: {
          version = "25.1.0";
          src = prev.fetchFromGitHub {
            owner = "psf";
            repo = "black";
            tag = "25.1.0";
            hash = "sha256-S9UopeXQ8vmG5JmE4SY+FclHV5GllRq8Y8pD4//xNiU=";
          };
          doCheck = false;
        });
      in
      {
        inline-snapshot = python-prev.inline-snapshot.override {
          black = black_25_1;
        };
      }
    )
  ];
}
