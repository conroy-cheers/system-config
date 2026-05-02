{
  system = "aarch64-linux";
  nixpkgs.variant = "default";

  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP55vChKcXZEZqtyvYLKJdH90nA+MzMp+1zoPC/RsnQD root@mainsailos";

  deploy = {
    hostname = "panda";
    sshUser = "conroy";
    user = "root";
    fastConnection = false;
    autoRollback = true;
    magicRollback = true;
    tempPath = "/tmp";
    remoteBuild = false;
  };
}
