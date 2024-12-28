# This file is not imported into the NixOS/home-manager configurations.
# It is only used for the `agenix` CLI.
# `agenix` use the public keys defined in this file to encrypt the secrets.
# Users can decrypt the secrets by any of the corresponding private keys.

let
  # User's ssh public key:
  #     cat ~/.ssh/id_ed25519.pub
  # Generate using:
  #     ssh-keygen -t ed25519
  main = "age1f0u4udt6y7qr9w74mk2d9a5g4d46qhpcuqxrljxuqe8wf00743uqm0980r"; # yubikey FIDO2
  users = [ main ];

  # System's ssh public key:
  #    cat /etc/ssh/ssh_host_ed25519_key.pub
  # Generated automatically when running `sshd`
  kombu_system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdi5yynd4jv2CUqM51TVT0hkPS6osXNc5bLq11dpB/f root@kombu";
  brick_system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUE2OxmW9PcRNvSY6wXsaxxoXNeRSYM2wj4UXR/pcW/ root@brick";
  systems = [ kombu_system brick_system ];
in
{
  "andromeda/aws-cache/env.age".publicKeys = users ++ [ kombu_system brick_system ];
  "andromeda/aws-experiments/key.age".publicKeys = users ++ [ kombu_system brick_system ];
  "andromeda/tailscale/key.age".publicKeys = users ++ [ kombu_system ];
  "corncheese/atuin/key.age".publicKeys = users ++ [ kombu_system brick_system ];
  "corncheese/home/key.age".publicKeys = users ++ [ kombu_system brick_system ];
  "home/conroy/user/password.age".publicKeys = users ++ [ kombu_system brick_system ];
  "home/wifi/conf.age".publicKeys = users ++ systems;
}
