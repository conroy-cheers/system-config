{
  lib,
  config,
  self,
  inputs,
  ...
}:

{
  imports = [ inputs.agenix-rekey.flakeModule ];

  perSystem = {
    agenix-rekey = {
      nodes =
        let
          mkUserEntries =
            hostName: cfg:
            lib.mapAttrs' (
              username: _:
              lib.nameValuePair "${hostName}-${username}" {
                config = cfg.config.home-manager.users.${username};
              }
            ) (cfg.config.home-manager.users or { });
        in
        (self.nixosConfigurations or { })
        // (lib.concatMapAttrs mkUserEntries (self.nixosConfigurations or { }))
        // (lib.concatMapAttrs mkUserEntries (self.darwinConfigurations or { }));
    };
  };
}
