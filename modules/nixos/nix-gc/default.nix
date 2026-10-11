{ lib, ... }:

{
  nix.gc = {
    automatic = true;
    dates = lib.mkDefault "daily";
    options = "--delete-older-than 7d";
  };
}
