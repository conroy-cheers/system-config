# SSH agents and Git signing

`corncheese.development.ssh.onePassword` configures Home Manager's
`sshAuthSock` integration. Local shells use the platform's 1Password socket;
SSH sessions preserve the forwarded socket when both `SSH_CONNECTION` and
`SSH_AUTH_SOCK` are set. GnuPG remains available for OpenPGP, with its SSH
support disabled on these workstations.

The same socket is published to systemd and D-Bus on Linux, and to launchd
on macOS for GUI applications. Keep the 1Password app running with its SSH
agent enabled. After applying the configuration, start a fresh desktop login
and restart existing GUI applications so they inherit the new environment.

SSH uses `SSH_AUTH_SOCK` without an `IdentityAgent` override. Git signs with
OpenSSH's `ssh-keygen` and the configured public signing key, so authentication
and signing use the same agent even for commands without a TTY. The agent on
the originating machine must contain the corresponding private keys.

## Forwarding

Forwarding remains disabled by default. Enable it for a connection:

```sh
ssh -A brick
```

Or opt a trusted destination into forwarding in the originating machine's
Home Manager configuration:

```nix
programs.ssh.settings."brick".ForwardAgent = true;
```

Forward only to machines you trust: processes with access to the remote
socket can request use of the originating machine's keys while connected.

Check a non-interactive connection:

```sh
ssh -A brick 'printf "%s\n" "$SSH_AUTH_SOCK"; ssh-add -l'
```

On the remote machine, `ssh -G github.com` should have no explicit
`identityagent` setting. `ssh -T git@github.com` should request authorization
on the originating machine when authorization is needed. GitHub exits with
status 1 even after successful authentication.
