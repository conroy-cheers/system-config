{ lib, ... }:

{
  nix.gc = {
    automatic = true;
    dates = lib.mkDefault "weekly";
    options = "--delete-older-than 7d";
  };
}
