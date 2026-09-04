{
  lib,
  identityData ? import ./ssh-identities.nix,
  hostData ? import ./nebula-hosts.nix,
}:

let
  inherit (lib) mkOption types;

  identityNames = builtins.attrNames identityData;

  checkedStringType =
    {
      name,
      description,
      check,
    }:
    types.mkOptionType {
      inherit name description;
      descriptionClass = "noun";
      check = value: types.str.check value && check value;
      inherit (types.str) merge;
    };

  sshPublicKeyType = checkedStringType {
    name = "sshPublicKey";
    description = "OpenSSH public key";
    check = key: builtins.match "(ssh|ecdsa|sk-ssh|sk-ecdsa)-[^ ]+ [^ ]+( .*)?" key != null;
  };
  identityFileNameType = checkedStringType {
    name = "sshPublicKeyFileName";
    description = "safe SSH public-key filename ending in .pub";
    check = fileName: builtins.match "[A-Za-z0-9._-]+\\.pub" fileName != null;
  };
  nebulaAddressType = checkedStringType {
    name = "ipv4Address";
    description = "IPv4 address";
    check =
      address:
      let
        octets = lib.splitString "." address;
        validOctet = octet: builtins.match "(0|[1-9][0-9]{0,2})" octet != null && lib.toInt octet <= 255;
      in
      builtins.length octets == 4 && lib.all validOctet octets;
  };
  userNameType = checkedStringType {
    name = "posixAccountName";
    description = "POSIX account name";
    check = user: builtins.match "[a-z_][a-z0-9_-]*" user != null;
  };

  evaluated = lib.evalModules {
    modules = [
      {
        _file = ./nebula-inventory.nix;

        options = {
          identities = mkOption {
            description = ''
              Named SSH client identities available to Nebula host aliases and
              destination authorized_keys configuration.
            '';
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    fileName = mkOption {
                      description = ''
                        Public-key filename installed under ~/.ssh for the
                        `${name}` identity. OpenSSH uses it to select the
                        corresponding private key from the configured agent.
                      '';
                      type = identityFileNameType;
                    };

                    publicKey = mkOption {
                      description = ''
                        OpenSSH public key for the `${name}` identity. The same
                        value is installed in each destination user's
                        authorized_keys.
                      '';
                      type = sshPublicKeyType;
                    };
                  };
                }
              )
            );
          };

          hosts = mkOption {
            description = ''
              Stable Nebula host inventory used for mesh addressing, generated
              SSH aliases, and destination key authorization.
            '';
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    address = mkOption {
                      description = ''
                        Stable IPv4 address embedded in `${name}`'s signed
                        Nebula certificate.
                      '';
                      type = nebulaAddressType;
                    };

                    lighthouse = mkOption {
                      description = ''
                        Optional static endpoints for a host that acts as a
                        Nebula lighthouse and relay.
                      '';
                      default = null;
                      type = types.nullOr (
                        types.submodule {
                          options.endpoints = mkOption {
                            description = "LAN and public UDP endpoints for this lighthouse";
                            type = types.nonEmptyListOf types.str;
                          };
                        }
                      );
                    };

                    ssh = mkOption {
                      description = ''
                        SSH destination policy for `${name}`. A null value means
                        that no SSH alias or managed authorized key is generated.
                      '';
                      default = null;
                      type = types.nullOr (
                        types.submodule {
                          options = {
                            user = mkOption {
                              description = ''
                                Existing destination account used by the
                                generated SSH alias.
                              '';
                              type = userNameType;
                            };

                            identity = mkOption {
                              description = ''
                                Named client identity selected for this alias
                                and authorized for the destination account.
                              '';
                              type = types.enum identityNames;
                            };
                          };
                        }
                      );
                    };
                  };
                }
              )
            );
          };
        };

      }
      {
        _file = ./ssh-identities.nix;
        config.identities = identityData;
      }
      {
        _file = ./nebula-hosts.nix;
        config.hosts = hostData;
      }
    ];
  };

  inventory = evaluated.config;
  hostAddresses = lib.mapAttrsToList (_: host: host.address) inventory.hosts;
  identityFileNames = lib.mapAttrsToList (_: identity: identity.fileName) inventory.identities;
  identityPublicKeys = lib.mapAttrsToList (_: identity: identity.publicKey) inventory.identities;
  lighthouseHosts = lib.filterAttrs (_: host: host.lighthouse != null) inventory.hosts;
  valuesAreUnique = values: builtins.length values == builtins.length (lib.unique values);
in
assert lib.assertMsg (valuesAreUnique hostAddresses) "Nebula host addresses must be unique";
assert lib.assertMsg (valuesAreUnique identityFileNames) "SSH identity filenames must be unique";
assert lib.assertMsg (valuesAreUnique identityPublicKeys) "SSH identity public keys must be unique";
assert lib.assertMsg (
  lighthouseHosts != { }
) "The Nebula inventory must define at least one lighthouse";
inventory
