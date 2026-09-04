{
  system = "x86_64-linux";
  nixpkgs.variant = "default";

  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMPRqpaOGbtiTG0tWSDTxqDP+6Y/5H2Pwq/Eyp4g+GHm root@hail";

  deploy = {
    hostname = "hail";
    sshUser = "conroy";
    user = "root";
    fastConnection = true;
    autoRollback = true;
    magicRollback = true;
    tempPath = "/tmp";
    remoteBuild = false;
  };
}
