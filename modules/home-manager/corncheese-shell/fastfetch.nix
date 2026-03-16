{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.corncheese.shell;

  nixosFastfetchLogoSvg = pkgs.fetchurl {
    url = "https://github.com/NixOS/branding/releases/download/nixos-branding-guide-v0.1.0/nixos-logomark-default-gradient-recommended.svg";
    sha256 = "0p4bx7p2rnxzmjfdad7iay661vgnh1ky2hpmm7ywa2scbrm59py1";
  };
  nixosFastfetchLogoPng =
    pkgs.runCommandLocal "nixos-fastfetch-logo.png"
      {
        nativeBuildInputs = [
          pkgs.librsvg
          pkgs.imagemagick
        ];
      }
      ''
        rsvg-convert --output rendered.png ${nixosFastfetchLogoSvg}
        magick rendered.png -alpha on -background none -trim +repage -resize 512 - | \
        magick - -alpha on -background none -trim +repage -gravity center -extent 512x512 -resize x512 "png32:$out"
      '';
  macosLogoPng =
    pkgs.runCommandLocal "macos-logo.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        magick ${./macos.png} -alpha on -background none -trim "png32:$out"
      '';

  baseSettings = {
    logo = {
      source = if pkgs.stdenv.hostPlatform.isDarwin then macosLogoPng else nixosFastfetchLogoPng;

      width = 10;
      height = 5;
      padding = {
        left = 2;
        top = 1;
        right = if pkgs.stdenv.hostPlatform.isDarwin then 2 else 1;
      };
    };

    display = {
      separator = " ›  ";
    };

    modules = [
      "break"
      {
        type = "os";
        key = "OS  ";
        keyColor = "31";
      }
      {
        type = "kernel";
        key = "KER ";
        keyColor = "32";
      }
      {
        type = "shell";
        key = "SH  ";
        keyColor = "34";
      }
      {
        type = "terminal";
        key = "TER ";
        keyColor = "35";
      }
      {
        type = "wm";
        key = "WM  ";
        keyColor = "36";
      }
    ];
  };

  localConfig = pkgs.writeText "fastfetch-local.jsonc" (
    builtins.toJSON (
      baseSettings
      // {
        logo = baseSettings.logo // {
          type = "kitty-direct";
        };
      }
    )
  );

  sshConfig = pkgs.writeText "fastfetch-ssh.jsonc" (
    builtins.toJSON (
      baseSettings
      // {
        logo = baseSettings.logo // {
          type = "kitty";
        };
      }
    )
  );

  fastfetchSmart = pkgs.symlinkJoin {
    name = "fastfetch-smart";
    paths = [ pkgs.fastfetch ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f $out/bin/fastfetch
      makeWrapper ${lib.getExe pkgs.fastfetch} $out/bin/fastfetch \
        --run '
          if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; then
            set -- --config ${sshConfig} "$@"
          else
            set -- --config ${localConfig} "$@"
          fi
        '
    '';
    meta.mainProgram = "fastfetch";
  };
in
{
  programs.fastfetch = {
    enable = true;
    package = fastfetchSmart;

    # Leave settings empty, since the wrapper supplies --config.
    settings = { };
  };

  programs.fish = lib.mkIf (builtins.elem "fish" cfg.shells) {
    functions = {
      fish_greeting = ''
        ${lib.getExe config.programs.fastfetch.package}
      '';
    };
  };
}
