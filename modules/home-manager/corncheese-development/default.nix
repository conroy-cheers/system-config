{
  inputs,
  config,
  lib,
  pkgs,
  meta,
  ...
}:

let
  cfg = config.corncheese.development;

  onePassPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''
    else
      "~/.1password/agent.sock";
  homeJumpHosts = [
    "pve"
    "bigbrain"
    "sleet"
  ];

  pkl-vscode = pkgs.vscode-utils.buildVscodeMarketplaceExtension rec {
    mktplcRef = {
      name = "pkl-vscode";
      version = "0.21.0";
      publisher = "apple";
    };
    vsix = builtins.fetchurl {
      url = "https://github.com/apple/pkl-vscode/releases/download/${mktplcRef.version}/pkl-vscode-${mktplcRef.version}.vsix";
      sha256 = "sha256:0jgbsxllqd1vhqzd83vv7bjg2hb951hqg6wflxxxalxvj4zlni79";
    };
  };
in
{
  imports = [
    inputs.vscode-server.homeModules.default
    inputs.nvf.homeManagerModules.default
  ];

  options = {
    corncheese.development = {
      ssh = {
        enable = lib.mkEnableOption "corncheese developer ssh config";
        onePassword = lib.mkEnableOption "corncheese developer ssh 1password integration";
      };
      vscode = {
        enable = lib.mkEnableOption "corncheese vscode config";
      };
      electronics = {
        enable = lib.mkEnableOption "corncheese electronics suite";
      };
      mechanical = {
        enable = lib.mkEnableOption "corncheese mechanical suite";
      };
      audio = {
        enable = lib.mkEnableOption "corncheese audio suite";
      };
      rust = {
        enable = lib.mkEnableOption "Rust development tools";
      };
      jetbrains = {
        enable = lib.mkEnableOption "corncheese jetbrains suite";
      };
      photo = {
        enable = lib.mkEnableOption "corncheese photo editing suite";
      };
    };
  };

  config = {
    services.vscode-server.enable = true;

    programs.vscode = lib.mkIf cfg.vscode.enable {
      enable = true;
      package = pkgs.vscodium;
      profiles.default =
        let
          nix-vscode-extensions = inputs.nix-vscode-extensions.extensions.${meta.system};
        in
        {
          enableUpdateCheck = false;
          enableExtensionUpdateCheck = false;
          extensions =
            with pkgs;
            builtins.concatLists [
              [
                # Visual
                vscode-extensions.catppuccin.catppuccin-vsc
                vscode-extensions.catppuccin.catppuccin-vsc-icons

                # Git
                vscode-extensions.eamodio.gitlens

                # Remote
                vscode-extensions.ms-vscode-remote.remote-ssh
                vscode-extensions.ms-vscode-remote.remote-ssh-edit

                # C++
                vscode-extensions.ms-vscode.cpptools-extension-pack
                vscode-extensions.xaver.clang-format
                vscode-extensions.ms-vscode.cmake-tools

                # Nix
                vscode-extensions.jnoortheen.nix-ide
                vscode-extensions.signageos.signageos-vscode-sops

                # Python
                vscode-extensions.ms-python.python
                nix-vscode-extensions.open-vsx.detachhead.basedpyright
                vscode-extensions.ms-python.debugpy
                vscode-extensions.charliermarsh.ruff
                vscode-extensions.njpwerner.autodocstring

                # Misc
                nix-vscode-extensions.open-vsx.tamasfe.even-better-toml
                vscode-extensions.fill-labs.dependi
                nix-vscode-extensions.open-vsx.openai.chatgpt

                # Pkl
                pkl-vscode
              ]
              (lib.optionals cfg.rust.enable [ vscode-extensions.rust-lang.rust-analyzer ])
              (lib.optionals (cfg.electronics.enable && cfg.rust.enable) [
                nix-vscode-extensions.open-vsx.probe-rs.probe-rs-debugger
              ])
            ];
          userSettings = {
            # General
            "extensions.autoUpdate" = false;
            "workbench.settings.editor" = "json";
            "explorer.confirmDelete" = false;
            "explorer.confirmDragAndDrop" = false;

            # Git
            "git.confirmSync" = false;
            "git.enableSmartCommit" = true;

            # Theming
            "editor.fontFamily" = lib.mkForce "MesloLGM Nerd Font Mono";
            "terminal.integrated.fontFamily" = lib.mkForce "MesloLGM Nerd Font Mono";
            "workbench.colorTheme" = lib.mkForce "Catppuccin Mocha";
            "workbench.iconTheme" = "catppuccin-mocha";

            # C++
            "cmake.pinnedCommands" = [
              "workbench.action.tasks.configureTaskRunner"
              "workbench.action.tasks.runTask"
            ];

            # Remote
            "remote.SSH.useLocalServer" = false;

            # Pkl
            "pkl.cli.path" = "${inputs.pkl-flake.packages.${meta.system}.default}/bin/pkl";

            # Nix
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = lib.getExe pkgs.nixd;
            "nix.serverSettings" = {
              "nixd" = {
                "formatting" = {
                  "command" = [ (lib.getExe pkgs.nixfmt) ];
                };
                "nixpkgs" = {
                  "expr" = "import (builtins.getFlake \"/home/conroy/.config/system-config\").inputs.nixpkgs { }";
                };
                "options" = {
                  "nixos" = {
                    "expr" =
                      "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options";
                  };
                  "home-manager" = {
                    "expr" =
                      "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options.home-manager.users.type.getSubOptions []";
                  };
                };
              };
            };
            "[nix]" = {
              "editor.formatOnSave" = true;
            };

            # Python
            "[python]" = {
              "editor.formatOnSave" = true;
              "editor.defaultFormatter" = "charliermarsh.ruff";
            };
            "ruff.enable" = true;
            "ruff.format.backend" = "internal";
            "ruff.importStrategy" = "fromEnvironment";
            "ruff.logLevel" = "debug";
            "autoDocstring.docstringFormat" = "one-line-sphinx";

            # Misc languages
            "redhat.telemetry.enabled" = false;
            "[toml]" = {
              "editor.formatOnSave" = true;
              "editor.defaultFormatter" = "tamasfe.even-better-toml";
            };
          };
        };
    };

    programs.nvf = {
      defaultEditor = true;
      enable = true;
      settings = {
        vim = {
          viAlias = true;
          vimAlias = true;

          lsp = {
            # This must be enabled for the language modules to hook into
            # the LSP API.
            enable = true;

            formatOnSave = true;
            lspkind.enable = false;
            lightbulb.enable = true;
            lspsaga.enable = false;
            trouble.enable = true;
            lspSignature.enable = false; # conflicts with blink in maximal
            otter-nvim.enable = true;
            nvim-docs-view.enable = true;
            harper-ls.enable = true;
          };

          debugger = {
            nvim-dap = {
              enable = true;
              ui.enable = true;
            };
          };

          # This section does not include a comprehensive list of available language modules.
          # To list all available language module options, please visit the nvf manual.
          languages = {
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;

            # Languages that will be supported in default and maximal configurations.
            nix.enable = true;
            markdown.enable = true;

            # Languages that are enabled in the maximal configuration.
            bash.enable = true;
            clang.enable = true;
            cmake.enable = true;
            css.enable = true;
            html.enable = true;
            json.enable = true;
            sql.enable = true;
            java.enable = false;
            kotlin.enable = false;
            ts.enable = true;
            go.enable = false;
            lua.enable = true;
            zig.enable = false;
            python.enable = true;
            typst.enable = false;
            rust = {
              enable = true;
              extensions.crates-nvim.enable = true;
            };
            toml.enable = true;
            xml.enable = true;

            # Language modules that are not as common.
            arduino.enable = false;
            assembly.enable = false;
            astro.enable = false;
            nu.enable = false;
            csharp.enable = false;
            julia.enable = false;
            vala.enable = false;
            scala.enable = false;
            r.enable = false;
            gleam.enable = false;
            glsl.enable = false;
            dart.enable = false;
            ocaml.enable = false;
            elixir.enable = false;
            haskell.enable = false;
            hcl.enable = false;
            ruby.enable = false;
            fsharp.enable = false;
            just.enable = false;
            make.enable = false;
            qml.enable = false;
            jinja.enable = false;
            tailwind.enable = false;
            svelte.enable = false;
            tera.enable = false;

            # Nim LSP is broken on Darwin and therefore
            # should be disabled by default. Users may still enable
            # `vim.languages.vim` to enable it, this does not restrict
            # that.
            # See: <https://github.com/PMunch/nimlsp/issues/178#issue-2128106096>
            nim.enable = false;
          };

          visuals = {
            nvim-scrollbar.enable = true;
            nvim-web-devicons.enable = true;
            nvim-cursorline.enable = true;
            cinnamon-nvim.enable = true;
            fidget-nvim.enable = true;

            highlight-undo.enable = true;
            blink-indent.enable = true;
            indent-blankline.enable = true;

            # Fun
            cellular-automaton.enable = false;
          };

          statusline = {
            lualine = {
              enable = true;
              theme = "catppuccin";
            };
          };

          theme = {
            enable = true;
            name = "catppuccin";
            style = "mocha";
            transparent = false;
          };

          autopairs.nvim-autopairs.enable = true;

          # nvf provides various autocomplete options. The tried and tested nvim-cmp
          # is enabled in default package, because it does not trigger a build. We
          # enable blink-cmp in maximal because it needs to build its rust fuzzy
          # matcher library.
          autocomplete = {
            nvim-cmp.enable = false;
            blink-cmp.enable = true;
          };

          snippets.luasnip.enable = true;

          filetree = {
            neo-tree = {
              enable = true;
            };
          };

          tabline = {
            nvimBufferline.enable = true;
          };

          treesitter.context.enable = true;

          binds = {
            whichKey.enable = true;
            cheatsheet.enable = true;
          };

          telescope.enable = true;

          git = {
            enable = true;
            gitsigns.enable = true;
            gitsigns.codeActions.enable = false; # throws an annoying debug message
            neogit.enable = false;
          };

          minimap = {
            minimap-vim.enable = true;
            codewindow.enable = false; # https://github.com/NotAShelf/nvf/issues/1426
          };

          dashboard = {
            dashboard-nvim.enable = false;
            alpha.enable = true;
          };

          notify = {
            nvim-notify.enable = true;
          };

          projects = {
            project-nvim.enable = true;
          };

          utility = {
            ccc.enable = false;
            vim-wakatime.enable = false;
            diffview-nvim.enable = true;
            yanky-nvim.enable = false;
            qmk-nvim.enable = false; # requires hardware specific options
            icon-picker.enable = true;
            surround.enable = true;
            leetcode-nvim.enable = true;
            multicursors.enable = true;
            smart-splits.enable = true;
            undotree.enable = true;
            nvim-biscuits.enable = false;
            grug-far-nvim.enable = true;

            motion = {
              hop.enable = true;
              leap.enable = true;
              precognition.enable = true;
            };
            images = {
              image-nvim.enable = false;
              img-clip.enable = true;
            };
          };

          notes = {
            neorg.enable = false;
            orgmode.enable = false;
            mind-nvim.enable = false;
            todo-comments.enable = true;
          };

          terminal = {
            toggleterm = {
              enable = true;
              lazygit.enable = true;
            };
          };

          ui = {
            borders.enable = true;
            noice.enable = true;
            colorizer.enable = true;
            modes-nvim.enable = false; # the theme looks terrible with catppuccin
            illuminate.enable = true;
            breadcrumbs = {
              enable = true;
              navbuddy.enable = true;
            };
            smartcolumn = {
              enable = true;
              setupOpts.custom_colorcolumn = {
                # this is a freeform module, it's `buftype = int;` for configuring column position
                nix = "110";
                ruby = "120";
                java = "130";
                go = [
                  "90"
                  "130"
                ];
              };
            };
            fastaction.enable = true;
          };

          assistant = {
            chatgpt.enable = false;
            copilot = {
              enable = false;
              cmp.enable = false;
            };
            codecompanion-nvim.enable = false;
            avante-nvim.enable = true;
          };

          session = {
            nvim-session-manager.enable = false;
          };

          gestures = {
            gesture-nvim.enable = false;
          };

          comments = {
            comment-nvim.enable = true;
          };

          presence = {
            neocord.enable = false;
          };
        };
      };
    };

    home.file = lib.mkMerge [
      (lib.mkIf cfg.ssh.enable (
        let
          # Get all files from the source directory
          sshFiles = builtins.readDir ./pubkeys;

          # Create a set of file mappings for each identity file
          fileMapper = filename: {
            # Target path will be in ~/.ssh/
            ".ssh/${filename}".source = ./pubkeys + "/${filename}";
          };
        in
        lib.mkMerge [
          (lib.foldl (acc: filename: acc // (fileMapper filename)) { } (builtins.attrNames sshFiles))
        ]
      ))
    ];

    xdg.configFile = lib.mkIf cfg.ssh.onePassword {
      "1Password/ssh/agent.toml".text = ''
        [[ssh-keys]]
        vault = "Private"
        item = "conroy-home"

        [[ssh-keys]]
        vault = "Private"
        item = "GitHub"

        [[ssh-keys]]
        vault = "Private"
        item = "github-signing-key"

        [[ssh-keys]]
        vault = "Work"
      '';
    };

    home.packages =
      with pkgs;
      builtins.concatLists [
        [
          # Nix
          nixd
          nixfmt
          nix-output-monitor

          # Git
          lazygit

          meld # Visual diff tool
          inputs.pkl-flake.packages.${meta.system}.default # pkl-cli
          pyright

          nerd-fonts.meslo-lg
          inputs.llm-agents.packages.${meta.system}.claude-code
          inputs.llm-agents.packages.${meta.system}.codex
          inputs.llm-agents.packages.${meta.system}.crush

          hoppscotch
        ]
        (lib.optionals cfg.electronics.enable (
          [
            kicad
            stm32cubemx
          ]
          ++ (lib.optionals (builtins.hasAttr "waveforms" pkgs) [ pkgs.waveforms ])
          ++ (lib.optionals (builtins.hasAttr "j-link" pkgs) [ pkgs.j-link ])
          ++ (lib.optionals (builtins.hasAttr "xtc-tools" pkgs) [ pkgs.xtc-tools ])
        ))
        (lib.optionals (cfg.electronics.enable && cfg.rust.enable) [
          probe-rs-tools
        ])
        (lib.optionals cfg.rust.enable [
          rustc
          cargo
          clippy
          rustfmt
          rust-analyzer
        ])
        (lib.optionals cfg.mechanical.enable [
          prusa-slicer
          # freecad-wayland  # https://github.com/NixOS/nixpkgs/issues/475536
        ])
        (lib.optionals cfg.audio.enable [ ardour ])
        (lib.optionals cfg.jetbrains.enable [
          (inputs.nix-jetbrains-plugins.lib.buildIdeWithPlugins pkgs "pycharm" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "systems.fehn.intellijdirenv"
            "nix-idea"
          ])
          (inputs.nix-jetbrains-plugins.lib.buildIdeWithPlugins pkgs "clion" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "systems.fehn.intellijdirenv"
            "nix-idea"
          ])
          (inputs.nix-jetbrains-plugins.lib.buildIdeWithPlugins pkgs "rust-rover" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "systems.fehn.intellijdirenv"
            "nix-idea"
          ])
        ])
        (lib.optionals cfg.photo.enable [
          (inputs.affinity.packages.${meta.system}.v3)
        ])
      ];

    # programs.jetbrains-remote = {
    #   enable = true;
    #   ides = with pkgs.jetbrains; [
    #     pycharm-professional
    #   ];
    # };

    programs.git = {
      enable = true;
      settings = {
        merge.tool = "meld";
        mergetool.meld.cmd = ''meld "$LOCAL" "$BASE" "$REMOTE" --output "$MERGED"'';
        diff.algorithm = "patience";
      };
      # TODO: move this to scm module
      ignores =
        let
          gitignoreSrc = pkgs.fetchFromGitHub {
            owner = "github";
            repo = "gitignore";
            rev = "ceea7cab239eece5cb9fd9416e433a9497c2d747";
            hash = "sha256-YOPkqYJXinGHCbuCpHLS76iIWqUvYZh6SaJ0ROGoHc4=";
          };
          gitignoreText = builtins.concatStringsSep "\n" (
            builtins.concatLists [
              (lib.optionals cfg.jetbrains.enable [
                (builtins.readFile "${gitignoreSrc}/Global/JetBrains.gitignore")
              ])
              (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
                (builtins.readFile "${gitignoreSrc}/Global/macOS.gitignore")
              ])
              (lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                (builtins.readFile "${gitignoreSrc}/Global/Linux.gitignore")
              ])
            ]
          );
        in
        lib.filter (value: !(lib.hasPrefix "#" value || value == "")) (lib.splitString "\n" gitignoreText);
    };

    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "beluga" = {
          hostname = "corncheese.org";
          user = "conroycheers";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "pve" = {
          hostname = "10.1.1.3";
          user = "root";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "bigbrain" = {
          hostname = "bigbrain.lan";
          user = "conroy";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "sleet" = {
          hostname = "sleet.lan";
          user = "conroy";
          identityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        home = {
          host = (lib.concatStringsSep " " homeJumpHosts);
          proxyJump = "beluga";
        };
        "*" = {
          forwardAgent = false;
          addKeysToAgent = "no";
          compression = false;
          identityAgent = onePassPath;
          hashKnownHosts = true;
        };
      };
    };
  };
}
