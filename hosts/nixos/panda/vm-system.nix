{ inputs }:
let
  pandaMeta = (import ./meta.nix) // {
    hostname = "panda";
  };
in
{
  meta = pandaMeta;

  modules = [
    {
      _module.args = {
        inherit inputs;
        meta = pandaMeta;
      };

      age.rekey.hostPubkey = pandaMeta.pubkey;
    }
    inputs.ragenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
    inputs.agenix-template.nixosModules.default
    ../../../modules/flake/configurations/agenix-rekey
    ./default.nix
    ./vm.nix
    {
      networking.hostName = "panda";
      system.stateVersion = "25.05";
    }
  ];
}
