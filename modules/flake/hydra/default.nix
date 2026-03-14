{ lib, config, ... }:

{
  flake.hydraJobs =
    let
      perSystemJobs =
        attr:
        lib.genAttrs config.systems (system: (config.perSystem system).${attr} or { });

      nixosHosts = config.auto.configurations.configurationTypes.nixos.result or { };
      darwinHosts = config.auto.configurations.configurationTypes."nix-darwin".result or { };
    in
    {
      packages = perSystemJobs "packages";
      checks = perSystemJobs "checks";

      nixosConfigurations = lib.mapAttrs (_: host: host.configuration.config.system.build.toplevel) nixosHosts;
      darwinConfigurations = lib.mapAttrs (_: host: host.configuration.system) darwinHosts;
    };
}
