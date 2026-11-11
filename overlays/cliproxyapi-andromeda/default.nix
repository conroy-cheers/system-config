_: prev: {
  cliproxyapi-andromeda = prev.cliproxyapi.overrideAttrs (old: {
    pname = "cliproxyapi-andromeda";
    patches = (old.patches or [ ]) ++ [ ./request-id.patch ];
  });
}
