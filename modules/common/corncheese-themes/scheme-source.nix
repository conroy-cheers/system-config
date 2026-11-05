{ pkgs }:
# Stylix reads palettes during evaluation. Fetch the same hash-pinned source
# as Nixpkgs directly so static themes also work when Hydra disables IFD.
builtins.fetchTarball {
  url = builtins.head pkgs.base16-schemes.src.urls;
  sha256 = pkgs.base16-schemes.src.outputHash;
}
