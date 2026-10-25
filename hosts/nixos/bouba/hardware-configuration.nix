{ inputs, ... }:
{
  hardware.steam-frame = {
    enable = true;
    dsp.remoteproc.enable = true;
    allowUnfreeHardwareSupport = true;
    layout = "nixos-only";
    storage.enable = true;
    ephemeralRoot.enable = true;
    # Original ESP PARTUUID: a79a43dd-1aac-461f-85a0-b3f50b387890.
    # Already provisioned; no disko/partitioning module is needed.
    streaming.countryCode = "AU";
    setupAccessPoint.enable = false;
    generationBoot = {
      enable = true;
      configurationLimit = 10;
      timeout = 5;
      chargingPolicy.enable = true;
      backgroundPreservation.enable = true;
      # The existing loader A already enters the menu. Publish catalog updates
      # without rewriting its saved firmware environment.
      automatic.enable = false;
      recoveryGenerations = [
        inputs.steam-frame-nixos.nixosConfigurations.frame-recovery.config.system.build.toplevel
      ];
    };
  };
}
