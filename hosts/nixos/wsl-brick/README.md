# wsl-brick

This is intended to be used as a WSL distro.

Build with:
```
sudo nix run .#nixosConfigurations.wsl-brick.config.system.build.tarballBuilder
```
This will create a `nixos-wsl.tar.gz` tarball in the working directory. Move it to a location accessible from Windows.

Import the tarball into WSL:
```
wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl.tar.gz --version 2
```
