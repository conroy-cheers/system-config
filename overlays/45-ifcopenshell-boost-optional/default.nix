_: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_: python-prev: {
      ifcopenshell = python-prev.ifcopenshell.overridePythonAttrs (old: {
        # Boost 1.91 requires explicit construction of optional fillet radii.
        patches = (old.patches or [ ]) ++ [ ./explicit-optional-radii.patch ];
      });
    })
  ];
}
