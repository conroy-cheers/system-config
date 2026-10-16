{
  system = "aarch64-linux";
  nixpkgs.variant = "default";
  pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID5vUE/KynwSEYdUJkm9SN2LqDxVQ5mk6x+rZFSFWLpb";
  deploy = {
    hostname = "bouba.lan";
    sshUser = "conroy";
    user = "root";
    sshOpts = [
      "-o"
      "IdentitiesOnly=yes"
      "-i"
      "~/.ssh/conroy_home.id_ed25519.pub"
    ];
    remoteBuild = true;
    autoRollback = true;
    magicRollback = true;
  };
}
