{
  inputs,
  meta,
  lib,
  pkgs,
  config,
  options,
  ...
}:
{
  config = {
    # NOTE: `(r)agenix` and `agenix-rekey` modules are imported by `../default.nix`
    age.rekey = {
      # NOTE: defined in `meta.nix`
      # hostPubkey       = null;
      masterIdentities = lib.mkDefault [
        {
          identity = "${inputs.self}/secrets/yubikey.hmac";
          pubkey = "age1f0u4udt6y7qr9w74mk2d9a5g4d46qhpcuqxrljxuqe8wf00743uqm0980r";
        }
      ];
      extraEncryptionPubkeys = lib.mkDefault inputs.self.secretsConfig.extraEncryptionPubkeys;
      storageMode = lib.mkDefault "local";
      localStorageDir = lib.mkDefault "${inputs.self}/secrets/rekeyed/${meta.hostname}";
      agePlugins = [ pkgs.age-plugin-fido2-hmac ];
    };
  };
}
