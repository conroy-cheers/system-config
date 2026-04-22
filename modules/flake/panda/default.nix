{
  lib,
  inputs,
  ...
}:
let
  pandaMeta = import "${inputs.self}/hosts/nixos/panda/meta.nix";
  vmSystem = import "${inputs.self}/hosts/nixos/panda/vm-system.nix" { inherit inputs; };
in
{
  perSystem =
    { system, ... }:
    let
      pkgsPure = inputs.nixpkgs.legacyPackages.${system};
      extractImage = pkgsPure.callPackage "${inputs.self}/pkgs/extract-image" { };
    in
    lib.mkMerge [
      (lib.mkIf (system == "x86_64-linux") {
        packages.panda-image-tool = pkgsPure.writeShellApplication {
          name = "extract-image";
          text = ''
            exec ${extractImage}/bin/extract-image \
              --expected-host-pubkey ${lib.escapeShellArg pandaMeta.pubkey} \
              "$@"
          '';
        };
      })

      (lib.mkIf (system == "x86_64-linux") {
        packages.panda-vm =
          (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = vmSystem.modules;
          }).config.system.build.vm;
      })
    ];
}
