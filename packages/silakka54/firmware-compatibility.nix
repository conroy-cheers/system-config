{
  # This ID is reported by firmware already in use. Keep it stable unless a
  # firmware change requires every connected keyboard half to be reflashed.
  id = "c91d546c9b251515db4e552e77441d1c4111b902dc300ee365f83e7a4bbe1d72";

  # The build fails when firmware-affecting inputs change without an explicit
  # compatibility decision. A non-semantic change may update only this value;
  # a flash-required change should also replace `id` with the new fingerprint.
  sourceFingerprint = "8448b24f43b4a58e899f5c2e9d1a8264eb341ca02c2d41923ee938c8aa38726c";
  vialJsonHash = "dc54ca84c52f0bcb388f66d571e24f3f953909fec632d3cf22038330978ac869";

  # QMK otherwise embeds the wall clock in the UF2 and its EEPROM magic.
  qmkBuildDate = "2026-05-20-00:00:00";
}
