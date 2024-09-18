{ config, lib, ... }:

let
  abiUser = "abi";
  abiHosts = [ "flabi" "abi2" "abi3" "abi10" ];
  homeJumpHosts = [ "pve" "bigbrain" ];
in  
{
  programs.ssh = {
    enable = true;
    forwardAgent = false;
    hashKnownHosts = true;

    matchBlocks = {
      "flabi-root" = {
        hostname = "abi-8152c13f";
        user = "root";
      };
      "flabi".hostname = "abi-8152c13f";
      "abi2".hostname = "abi-498fc35d";
      "abi3".hostname = "abi-49e564ed";
      "abi10".hostname = "abi-0896ad9a";
      abi = {
        host = (lib.concatStringsSep " " abiHosts);
        user = abiUser;
        extraOptions = {
          PubkeyAuthentication = "no";
        };
      };

      "beluga" = {
        hostname = "corncheese.org";
        user = "conroycheers";
      };
      "pve" = {
        hostname = "10.1.1.3";
        user = "root";
      };
      "bigbrain" = {
        hostname = "bigbrain.lan";
        user = "conroy";
      };
      home = {
        host = (lib.concatStringsSep " " homeJumpHosts);
        proxyJump = "beluga";
      };
    };
  };
}