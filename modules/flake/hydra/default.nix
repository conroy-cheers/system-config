{
  lib,
  config,
  ...
}:

{
  flake.hydraJobs =
    let
      systems = lib.filter (system: system == "x86_64-linux") config.systems;

      packageJobs = lib.genAttrs systems (
        system:
        let
          jobs = (config.perSystem system).packages or { };
          pkgs = (config.perSystem system).pkgs.default;
          availableJobs = lib.filterAttrs (_: job: lib.meta.availableOn pkgs.stdenv.hostPlatform job) jobs;
        in
        lib.getAttrs (builtins.attrNames availableJobs) jobs
      );

      checkJobs = lib.genAttrs systems (
        system:
        let
          jobs = (config.perSystem system).checks or { };
        in
        lib.getAttrs (builtins.attrNames config.auto.checks.result) jobs
      );

      configurationJobs =
        hosts:
        let
          jobs = lib.mapAttrs (_: host: host.configuration.config.system.build.toplevel) hosts;
        in
        lib.getAttrs (builtins.attrNames hosts) jobs;

      nixosHosts = config.auto.configurations.configurationTypes.nixos.result or { };
      darwinHosts =
        (lib.attrByPath [ "nix-darwin" ] { } config.auto.configurations.configurationTypes).result or { };
    in
    {
      packages = packageJobs;
      checks = checkJobs;

      nixosConfigurations = configurationJobs nixosHosts;
      darwinConfigurations = configurationJobs darwinHosts;
    };
}
