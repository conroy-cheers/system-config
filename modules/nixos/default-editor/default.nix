{
  lib,
  pkgs,
  config,
  ...
}:

with lib;
let
in
{
  programs.nano.enable = false;
}
