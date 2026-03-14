{ lib, config, ... }:

{
  flake.hydraJobs =
    let
      filterEvaluableJobs =
        jobs:
        lib.filterAttrs (
          _: job:
          lib.isDerivation job
          && (builtins.tryEval job.drvPath).success
        ) jobs;

      filterEvaluableHostJobs =
        jobs:
        lib.filterAttrs (
          _: job:
          lib.isDerivation job
          && (builtins.tryEval job.drvPath).success
        ) jobs;

      filterHydraChecks =
        checks:
        lib.filterAttrs (name: _: !(lib.hasPrefix "deploy-" name)) checks;

      perSystemJobs =
        attr:
        lib.genAttrs (lib.filter (system: system == "x86_64-linux") config.systems) (
          system:
          let
            jobs = (config.perSystem system).${attr} or { };
            filteredJobs =
              if attr == "checks" then filterHydraChecks jobs else jobs;
          in
          filterEvaluableJobs filteredJobs
        );

      nixosHosts = config.auto.configurations.configurationTypes.nixos.result or { };
    in
    {
      packages = perSystemJobs "packages";
      checks = perSystemJobs "checks";

      nixosConfigurations = filterEvaluableHostJobs (
        lib.mapAttrs (_: host: host.configuration.config.system.build.toplevel) nixosHosts
      );
      darwinConfigurations = { };
    };
}
