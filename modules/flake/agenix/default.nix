{
  lib,
  config,
  self,
  inputs,
  ...
}:

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
{
  imports = [ inputs.agenix-rekey.flakeModule ];

  perSystem = {
    agenix-rekey = {
      # userFlake = self;
      nixosConfigurations = self.nixosConfigurations // self.darwinConfigurations;
      homeConfigurations =
        (lib.concatMapAttrs mkUserEntries (self.nixosConfigurations or { }))
        // (lib.concatMapAttrs mkUserEntries (self.darwinConfigurations or { }));
      # nodes =
      #   (self.nixosConfigurations or { })
      #   // (self.darwinConfigurations or { })
      #   // (lib.concatMapAttrs mkUserEntries (self.nixosConfigurations or { }))
      #   // (lib.concatMapAttrs mkUserEntries (self.darwinConfigurations or { }));
    };
  };
}
