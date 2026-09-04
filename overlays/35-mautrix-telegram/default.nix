_: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _: python-prev:
      prev.lib.optionalAttrs (python-prev ? mautrix-telegram) {
        # nixpkgs already carries a patch converting pkg_resources to
        # importlib.resources. Its postPatch repeats the same strict
        # substitutions, so the second pass fails after the patch succeeds.
        mautrix-telegram = python-prev.mautrix-telegram.overridePythonAttrs (_: {
          postPatch = "";
        });
      }
    )
  ];
}
