{ lib, pkgs, config, ... }:

let
  cfg = config.corncheese.shell;

  inherit (lib)
    mkEnableOption mkOption types
    mkIf optionals optionalString
    mkMerge;

  shellAliases = {
    s = "kitten ssh";
    cp = "${pkgs.fcp}/bin/fcp";
    rebuild =
      let
        rebuild_script = pkgs.writeShellScript "rebuild" ''
          ${
            let
              inherit (lib.strings)
                hasInfix;
              inherit (pkgs.hostPlatform)
                isx86_64 isAarch64
                isLinux isDarwin;
            in
            if isx86_64 && isLinux then
              "sudo --validate && sudo nixos-rebuild"
            else if isDarwin then
              "darwin-rebuild"
            else if isAarch64 then
              "nix-on-droid"
            else
              "home-manager"
          } --flake ${
            if cfg.hostname != null
            then "${cfg.flakePath}#${cfg.hostname}"
            else "${cfg.flakePath}"
          } ''$''\{1:-switch''\} "''$''\{@:2''\}" # |& nix run nixpkgs#nix-output-monitor
        '';
      in
      "${rebuild_script}";
  };
in
{
  imports =
    [
    ];

  options =
    {
      corncheese.shell = {
        enable = mkEnableOption "corncheese shell setup";
        username = mkOption {
          description = "Username to be used (for prompt)";
          type = types.str;
          default = "${config.home.username}";
        };
        hostname = mkOption {
          description = "Hostname to be used (for `rebuild`)";
          type = types.nullOr types.str;
          default = null;
        };
        shells = mkOption {
          description = "Shells to be configured (first one is used for $SHELL)";
          type =
            lib.pipe
              [
                "nushell"
                "zsh"
              ]
              [
                types.enum
                types.listOf
              ];
          default = [ "nushell" "zsh" ];
        };
        starship = mkOption {
          description = "Use starship prompt";
          type = types.bool;
          default = false;
        };
        p10k = mkOption {
          description = "Use powerlevel10k";
          type = types.bool;
          default = true;
        };
        atuin = mkOption {
          description = "Integrate with atuin";
          type = types.bool;
          default = true;
        };
        direnv = mkOption {
          description = "Integrate with direnv";
          type = types.bool;
          default = true;
        };
        zoxide = mkOption {
          description = "Integrate with zoxide";
          type = types.bool;
          default = true;
        };
        flakePath = mkOption {
          description = "Flake path (for `rebuild`)";
          type = types.str;
          default = "${config.xdg.configHome}/rix101";
        };
      };
    };

  config =
    mkIf cfg.enable {
      home.packages = with pkgs;
        builtins.concatLists [
          (builtins.map
            (lib.flip builtins.getAttr pkgs)
            cfg.shells)
          (optionals cfg.starship [
            starship
          ])
          (optionals cfg.p10k [
            zsh-powerlevel10k
          ])
          (optionals cfg.direnv [
            direnv
          ])
          (optionals cfg.zoxide [
            zoxide
          ])
        ];

      # Direnv
      programs.direnv = mkIf cfg.direnv {
        enable = true;

        enableNushellIntegration = builtins.elem "nushell" cfg.shells;
        enableZshIntegration = builtins.elem "zsh" cfg.shells;

        nix-direnv = {
          enable = true;
        };
      };

      # Atuin
      programs.atuin = mkIf cfg.atuin {
        enable = true;

        enableNushellIntegration = builtins.elem "nushell" cfg.shells;
        enableZshIntegration = builtins.elem "zsh" cfg.shells;
      };

      # Bat
      programs.bat = {
        enable = true;
      };

      # Starship
      programs.starship = mkIf cfg.starship {
        enable = true;

        package = pkgs.starship;

        settings = import ./starship.nix {
          inherit (cfg) username;
        };
      };

      # Zoxide
      programs.zoxide = mkIf cfg.zoxide {
        enable = true;

        package = pkgs.zoxide;

        enableNushellIntegration = builtins.elem "nushell" cfg.shells;
        enableZshIntegration = builtins.elem "zsh" cfg.shells;
      };

      # GnuPG
      services.gpg-agent = {
        enableNushellIntegration = builtins.elem "nushell" cfg.shells;
        enableZshIntegration = builtins.elem "zsh" cfg.shells;
      };

      # Shell
      home.sessionVariables = {
        SHELL =
          let
            shellPackage = builtins.getAttr (builtins.head cfg.shells) pkgs;
          in
          "${shellPackage}/${shellPackage.shellPath}";
      };

      # Nushell
      programs.nushell = mkMerge [
        (mkIf (builtins.elem "nushell" cfg.shells) {
          enable = true;

          package = pkgs.nushell;

          configFile.source = ./nushell/config.nu;
          envFile.source = ./nushell/env.nu;
          loginFile.source = ./nushell/login.nu;

          inherit shellAliases;

          environmentVariables = { };
        })
      ];

      # Zsh
      programs.zsh = mkIf (builtins.elem "zsh" cfg.shells) {
        enable = true;
        package = pkgs.zsh;

        enableCompletion = true;

        dotDir = ".config/zsh";

        shellAliases = shellAliases // {
          ls = "${pkgs.lsd}/bin/lsd";
          mkdir = "mkdir -vp";
        };

        history = {
          size = 50000;
          path = "${config.xdg.dataHome}/zsh/history";
        };

        initExtra =
          builtins.concatStringsSep "\n"
            [
              ''
                function take() {
                  mkdir -p "''$''\{@''\}" && cd "''$''\{@''\}"
                }
              ''
              (optionalString cfg.p10k ''
                source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme  
                test -f ~/.config/zsh/.p10k.zsh && source ~/.config/zsh/.p10k.zsh
              '')
              # NOTE: done by `programs.direnv`
              # (optionalString cfg.direnv ''
              #   eval "$(${pkgs.direnv}/bin/direnv hook zsh)"
              # '')
              # NOTE: done by `programs.zoxide`
              # (optionalString cfg.zoxide ''
              #   eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
              # '')
              ''
                # Prevent macOS updates from destroying nix
                if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ] && [ "''$''\{SHLVL''\}" -eq 1 ]; then
                  source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
                fi
              ''
              ''
                bindkey '^[[1;3D' backward-word  # Alt + Left
                bindkey '^[[1;3C' forward-word   # Alt + Right
              ''
              # cfg.extraConfig
            ];

        plugins = [
          {
            name = "zsh-nix-shell";
            file = "nix-shell.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "chisui";
              repo = "zsh-nix-shell";
              rev = "v0.8.0";
              hash = "sha256-Z6EYQdasvpl1P78poj9efnnLj7QQg13Me8x1Ryyw+dM=";
            };
          }
          {
            name = "fast-syntax-highlighting";
            file = "fast-syntax-highlighting.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "zdharma-continuum";
              repo = "fast-syntax-highlighting";
              rev = "cf318e06a9b7c9f2219d78f41b46fa6e06011fd9";
              hash = "sha256-RVX9ZSzjBW3LpFs2W86lKI6vtcvDWP6EPxzeTcRZua4=";
            };
          }
          {
            name = "zsh-autosuggestions";
            file = "zsh-autosuggestions.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "zsh-users";
              repo = "zsh-autosuggestions";
              rev = "c3d4e576c9c86eac62884bd47c01f6faed043fc5";
              hash = "sha256-B+Kz3B7d97CM/3ztpQyVkE6EfMipVF8Y4HJNfSRXHtU=";
            };
          }
          {
            name = "zsh-bat";
            file = "zsh-bat.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "fdellwing";
              repo = "zsh-bat";
              rev = "c47f2de99d0c4c778e9de56ac8e527ddfd9b02e2";
              hash = "sha256-7TL47mX3eUEPbfK8urpw0RzEubGF2x00oIpRKR1W43k=";
            };
          }
          (mkIf cfg.p10k
            ({
              name = "powerlevel10k";
              file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
              src = pkgs.zsh-powerlevel10k;
            })
          )
        ];
      };
    };

  meta = {
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
}
