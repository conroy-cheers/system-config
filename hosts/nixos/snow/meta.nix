{
  system = "x86_64-linux";
  nixpkgs.variant = "default";

  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF1a117TEFHlV4kUPmiNsiJblRzYMDlSm4LBVB/jR04p root@snow";

  deploy = {
    hostname = "snow";
    sshUser = "conroy";
    user = "root";
    fastConnection = true;
    autoRollback = true;
    magicRollback = true;
    tempPath = "/tmp";
    remoteBuild = true;
  };
}
