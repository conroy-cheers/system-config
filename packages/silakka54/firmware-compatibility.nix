{
  # This ID is reported by firmware already in use. Keep it stable unless a
  # firmware change requires every connected keyboard half to be reflashed.
  id = "5aa87e47f855652599500cf3db90c1f07b4b7609810bbc24dd39505b80a6c289";

  # The build fails when firmware-affecting inputs change without an explicit
  # compatibility decision. A non-semantic change may update only this value;
  # a flash-required change should also replace `id` with the new fingerprint.
  sourceFingerprint = "5aa87e47f855652599500cf3db90c1f07b4b7609810bbc24dd39505b80a6c289";
  vialJsonHash = "dc54ca84c52f0bcb388f66d571e24f3f953909fec632d3cf22038330978ac869";

  # QMK otherwise embeds the wall clock in the UF2 and its EEPROM magic.
  qmkBuildDate = "2026-05-20-00:00:00";
}
