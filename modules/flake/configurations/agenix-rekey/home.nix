{
  inputs,
  lib,
  pkgs,
  config,
  options,
  meta,
  ...
}:
{
  config = {
    # Set fixed secrets dirs so we can reference secrets with a constant path
    age = {
      secretsDir = "${config.home.homeDirectory}/.agenix/agenix";
      secretsMountPoint = "${config.home.homeDirectory}/.agenix/agenix.d";
    };
    # NOTE: `(r)agenix` and `agenix-rekey` modules are imported by `../../../modules/flake/configurations.nix`
    age.rekey = {
      # NOTE: defined in user home-manager config
      # hostPubkey       = null;
      masterIdentities = lib.mkDefault [
        {
          identity = "${inputs.self}/secrets/yubikey.hmac";
          pubkey = "age1f0u4udt6y7qr9w74mk2d9a5g4d46qhpcuqxrljxuqe8wf00743uqm0980r";
        }
      ];
      storageMode = lib.mkDefault "local";
      localStorageDir = lib.mkDefault "${inputs.self}/secrets/rekeyed/${meta.hostname}-${config.home.username}";
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
    };
  };
}
