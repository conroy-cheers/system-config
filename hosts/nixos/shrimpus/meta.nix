{
  system = "aarch64-linux";
  nixpkgs.variant = "default";
  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB2xRkFpNqlT7CSgCF+EG9EwVcf1RD/4W2EaiN6AZd/E root@shrimpus";

  deploy = {
    hostname = "shrimpus.local";
    sshUser = "conroy";
    sshOpts = [
      "-o"
      "IdentitiesOnly=yes"
      "-i"
      "~/.ssh/conroy_home.id_ed25519.pub"
    ];
    user = "root";
    fastConnection = false;
    autoRollback = true;
    magicRollback = true;
    tempPath = "/tmp";
    remoteBuild = false;
  };
}
