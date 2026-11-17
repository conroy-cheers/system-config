_: prev: {
  feishin = prev.feishin.overrideAttrs (old: {
    # mpris-service guesses doubles for every numeric Xesam field. BlueZ rejects
    # the player when xesam:trackNumber is not an integer, breaking AVRCP controls.
    preBuild = (old.preBuild or "") + ''
      patch -d node_modules/mpris-service -p1 < ${./mpris-integer-metadata.patch}
    '';
  });
}
