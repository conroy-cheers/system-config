{
  callPackage,
}:
let
  maple-font = callPackage ./maple-font.nix { };
in
maple-font.NF-CN
