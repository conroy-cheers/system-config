_: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_: python-prev: {
      diff-cover = python-prev.diff-cover.overridePythonAttrs (oldAttrs: {
        postPatch = (oldAttrs.postPatch or "") + ''
          # Current Pygments leaves quotes unescaped in HTML text nodes.
          for report in tests/fixtures/*violations_report*.html; do
            substituteInPlace "$report" --replace-fail '&quot;' '"'
          done
        '';
      });
    })
  ];
}
