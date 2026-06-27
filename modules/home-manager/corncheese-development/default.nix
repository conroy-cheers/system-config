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
  themeDetails =
    if config.corncheese.theming.enable then config.corncheese.theming.themeDetails else { };
  colorshellEnabled = lib.attrByPath [ "programs" "colorshell" "enable" ] false config;
  walbridgeRuntimeThemeEnabled = pkgs.stdenv.hostPlatform.isLinux && colorshellEnabled;

  codexHome = "${config.home.homeDirectory}/.codex";
  codexConfigFile = "${codexHome}/config.toml";
  codexConfig = (pkgs.formats.toml { }).generate "codex-config.toml" {
    mcp_servers.ReVa = {
      command = lib.getExe pkgs.reverse-engineering-assistant;
      default_tools_approval_mode = "prompt";
      startup_timeout_sec = 90;
      tool_timeout_sec = 300;
    };
  };
  codexRemovedNixMcpServers = [
    "slack"
  ];
  codexMergePython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.tomlkit
  ]);
  codexMergeScript = pkgs.writeText "merge-codex-config.py" ''
    import os
    import sys
    from pathlib import Path

    import tomlkit


    def merge_config(existing, desired):
        for key, desired_value in desired.items():
            if key in existing and mergeable(existing[key], desired_value):
                merge_config(existing[key], desired_value)
            else:
                existing[key] = desired_value


    def mergeable(existing_value, desired_value):
        return hasattr(existing_value, "items") and hasattr(desired_value, "items")


    def remove_mcp_server(config, name):
        mcp_servers = config.get("mcp_servers")
        if hasattr(mcp_servers, "pop"):
            mcp_servers.pop(name, None)


    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    target.parent.mkdir(parents=True, exist_ok=True)

    desired_config = tomlkit.parse(source.read_text())
    existing_config = tomlkit.document()
    if target.exists() or target.is_symlink():
        try:
            existing_config = tomlkit.parse(target.read_text())
        except FileNotFoundError:
            pass

    if target.is_symlink():
        target.unlink()

    merge_config(existing_config, desired_config)
    for removed_mcp_server in sys.argv[3:]:
        remove_mcp_server(existing_config, removed_mcp_server)

    tmp = target.with_name(f"{target.name}.tmp")
    tmp.write_text(tomlkit.dumps(existing_config))
    os.replace(tmp, target)
  '';
  mergeCodexConfig = pkgs.writeShellScript "merge-codex-config" ''
    ${codexMergePython}/bin/python \
      ${codexMergeScript} \
      ${codexConfig} \
      "${codexConfigFile}" \
      ${lib.escapeShellArgs codexRemovedNixMcpServers}
  '';

  onePassPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''
    else
      "~/.1password/agent.sock";
  homeJumpHosts = [
    "pve"
    "bigbrain"
    "sleet"
    "alexandria"
    "panda"
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

  codex-wrapped = pkgs.symlinkJoin {
    name = "codex-wrapped";
    paths = [ inputs.codex-flake.packages.${meta.system}.codex ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      wrapProgram $out/bin/codex \
        --prefix PATH : ${
          lib.makeBinPath (
            with pkgs;
            [
              ripgrep
              fd
              gnused
              gawk
              jq
              curl
              wget2
              gnutar
              unzip
              just
              reverse-engineering-assistant
            ]
            ++ (lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              bubblewrap
            ])
          )
        }
    '';
  };

  claude-code-wrapped = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [ inputs.llm-agents.packages.${meta.system}.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      wrapProgram $out/bin/claude \
        --add-flags --dangerously-skip-permissions \
        --prefix PATH : ${
          lib.makeBinPath (
            with pkgs;
            [
              gh
              jq
              yq
              curl
              python3
              openssl
              ripgrep
              fd
              dig
              tree
              file
              xxd
              bc
              sqlite
              envsubst
              gnutar
              gzip
              unzip
              zstd
              shellcheck
              findutils
              diffutils
              patch
              nix-diff
              lsof
              gnused
              gawk

              nmap
              tcpdump
              socat
              netcat
              curl
              wget2
            ]
          )
        }
    '';
  };
in
{
  imports = [
    "${inputs.vscode-server}/modules/vscode-server/home.nix"
    inputs.nvf.homeManagerModules.default
  ];

  options = {
    corncheese.development = {
      enable = lib.mkEnableOption "corncheese development environment";
      ssh = {
        enable = lib.mkEnableOption "corncheese developer ssh config";
        onePassword = lib.mkEnableOption "corncheese developer ssh 1password integration";
        zellij = {
          enable = lib.mkOption {
            description = "Automatically attach interactive SSH logins to a zellij session.";
            type = lib.types.bool;
            default = cfg.ssh.enable;
          };
          sessionName = lib.mkOption {
            description = "Zellij session name used for interactive SSH logins.";
            type = lib.types.str;
            default = "ssh";
          };
        };
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

  config = lib.mkIf cfg.enable {
    services.vscode-server.enable = true;

    programs.vscodium = lib.mkIf cfg.vscode.enable {
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
          }
          // lib.optionalAttrs walbridgeRuntimeThemeEnabled {
            "workbench.colorTheme" = lib.mkForce "Walbridge";
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

          clipboard = {
            enable = true;
            registers = "unnamedplus";
            providers.wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
          };

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
            presets.harper.enable = true;

            servers.nixd.settings.nixd = {
              nixpkgs.expr = "import (builtins.getFlake \"/home/conroy/.config/system-config\").inputs.nixpkgs { }";
              options = {
                nixos.expr = "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options";
                home-manager.expr = "(builtins.getFlake \"/home/conroy/.config/system-config\").nixosConfigurations.${meta.hostname}.options.home-manager.users.type.getSubOptions []";
              };
            };
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
            nix = {
              enable = true;
              lsp.servers = [ "nixd" ];
              format.type = [ "nixfmt" ];
            };
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
            typescript.enable = true;
            go.enable = false;
            lua.enable = true;
            zig.enable = false;
            python = {
              enable = true;
              format.type = [ "ruff" ];
            };
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
              theme = lib.mkForce "catppuccin";
            };
          };

          theme = {
            enable = true;
            name = lib.mkForce "catppuccin";
            style = "mocha";
            transparent = themeDetails.terminalTuiTransparent or false;
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
            colorizer = {
              enable = true;
              setupOpts.filetypes."*" = { };
            };
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
            ".ssh/${filename}".source = pkgs.copyPathToStore (./pubkeys + "/${filename}");
          };
        in
        lib.mkMerge [
          (lib.foldl (acc: filename: acc // (fileMapper filename)) { } (builtins.attrNames sshFiles))
        ]
      ))
    ];

    xdg.configFile = lib.mkIf cfg.ssh.onePassword {
      "1Password/ssh/agent.toml".text = lib.mkAfter ''
        [[ssh-keys]]
        vault = "Private"
        item = "GitHub"

        [[ssh-keys]]
        vault = "Private"
        item = "github-signing-key"

        [[ssh-keys]]
        vault = "Private"
        item = "conroy-home"
      '';
    };

    home.activation.mergeCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${mergeCodexConfig}
    '';

    systemd.user.services.codex-config-merge = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "Merge Codex config with Nix-defined configuration";
        After = [ "default.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${mergeCodexConfig}";
        RemainAfterExit = true;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    launchd.agents.codex-config-merge = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${mergeCodexConfig}" ];
        ProcessType = "Background";
        RunAtLoad = true;
      };
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
          git-spice
          inputs.weave.packages.${meta.system}.default

          meld # Visual diff tool
          inputs.pkl-flake.packages.${meta.system}.default # pkl-cli
          pyright

          nerd-fonts.meslo-lg
          nodejs-slim
          tmux
          claude-code-wrapped
          codex-wrapped

          ghidra

          hoppscotch
        ]
        (lib.optionals cfg.ssh.zellij.enable [
          zellij
        ])
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
          rustup
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
            "nix-idea"
          ])
          (inputs.nix-jetbrains-plugins.lib.buildIdeWithPlugins pkgs "clion" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "nix-idea"
          ])
          (inputs.nix-jetbrains-plugins.lib.buildIdeWithPlugins pkgs "rust-rover" [
            "com.intellij.plugins.vscodekeymap"
            "com.github.catppuccin.jetbrains"
            "nix-idea"
          ])
        ])
        (lib.optionals cfg.photo.enable [
          pkgs.affinity-v3
        ])
      ];

    home.sessionVariables = {
      GIT_SPICE_NO_GS_WARNING = "1";
    };

    programs.fish.interactiveShellInit = lib.mkIf cfg.ssh.zellij.enable (
      lib.mkAfter ''
        if test -n "$SSH_TTY$SSH_CONNECTION"; and test -z "$ZELLIJ"; and test -z "$SSH_ORIGINAL_COMMAND"; and test "$TERM" != dumb; and test -t 0; and test -t 1
            exec ${lib.getExe pkgs.zellij} attach --create ${lib.escapeShellArg cfg.ssh.zellij.sessionName}
        end
      ''
    );

    programs.zsh.initContent = lib.mkIf cfg.ssh.zellij.enable (
      lib.mkAfter ''
        if [[ -o interactive && -n "''${SSH_TTY:-}''${SSH_CONNECTION:-}" && -z "''${ZELLIJ:-}" && -z "''${SSH_ORIGINAL_COMMAND:-}" && "''${TERM:-}" != dumb && -t 0 && -t 1 ]]; then
          exec ${lib.getExe pkgs.zellij} attach --create ${lib.escapeShellArg cfg.ssh.zellij.sessionName}
        fi
      ''
    );

    programs.bash.initExtra = lib.mkIf cfg.ssh.zellij.enable (
      lib.mkAfter ''
        if [[ $- == *i* && -n "''${SSH_TTY:-}''${SSH_CONNECTION:-}" && -z "''${ZELLIJ:-}" && -z "''${SSH_ORIGINAL_COMMAND:-}" && "''${TERM:-}" != dumb && -t 0 && -t 1 ]]; then
          exec ${lib.getExe pkgs.zellij} attach --create ${lib.escapeShellArg cfg.ssh.zellij.sessionName}
        fi
      ''
    );

    # programs.jetbrains-remote = {
    #   enable = true;
    #   ides = with pkgs.jetbrains; [
    #     pycharm-professional
    #   ];
    # };

    programs.git = {
      enable = true;
      settings = {
        merge = {
          tool = "meld";
          weave = {
            name = "Entity-level semantic merge";
            driver = "${inputs.weave.packages.${meta.system}.default}/bin/weave-driver %O %A %B %L %P";
          };
        };
        mergetool.meld.cmd = ''meld "$LOCAL" "$BASE" "$REMOTE" --output "$MERGED"'';
        diff.algorithm = "patience";
      };
      attributes = map (extension: "${extension} merge=weave") [
        "*.ts"
        "*.tsx"
        "*.js"
        "*.mjs"
        "*.cjs"
        "*.jsx"
        "*.py"
        "*.go"
        "*.rs"
        "*.java"
        "*.c"
        "*.h"
        "*.cpp"
        "*.cc"
        "*.cxx"
        "*.hpp"
        "*.hh"
        "*.hxx"
        "*.rb"
        "*.cs"
        "*.php"
        "*.swift"
        "*.ex"
        "*.exs"
        "*.sh"
        "*.f90"
        "*.f95"
        "*.f03"
        "*.f08"
        "*.xml"
        "*.plist"
        "*.svg"
        "*.csproj"
        "*.fsproj"
        "*.vbproj"
        "*.json"
        "*.yaml"
        "*.yml"
        "*.toml"
        "*.md"
        "*.scala"
        "*.sc"
        "*.sbt"
        "*.kojo"
        "*.mill"
        "*.dart"
      ];
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

    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };

    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      enableDefaultConfig = false;

      settings = {
        "beluga" = {
          HostName = "corncheese.org";
          User = "conroycheers";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
          IdentitiesOnly = true;
        };
        "snow" = {
          HostName = "10.1.1.120";
          User = "conroy";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
          IdentitiesOnly = true;
        };
        "snow-bastion" = {
          HostName = "corncheese.org";
          User = "conroy";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
          IdentitiesOnly = true;
        };
        "pve" = {
          HostName = "10.1.1.3";
          User = "root";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "bigbrain" = {
          HostName = "bigbrain.lan";
          User = "conroy";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "sleet" = {
          HostName = "sleet.lan";
          User = "conroy";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "alexandria" = {
          HostName = "10.1.1.30";
          User = "root";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "haos" = {
          HostName = "10.1.1.114";
          Port = 22222;
          User = "root";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        "panda" = {
          HostName = "panda.lan";
          User = "conroy";
          IdentityFile = "${config.home.homeDirectory}/.ssh/conroy_home.id_ed25519.pub";
        };
        home = {
          header = "Host ${lib.concatStringsSep " " homeJumpHosts}";
          ProxyJump = "beluga";
          IdentitiesOnly = true;
        };
        "*" = {
          ForwardAgent = false;
          AddKeysToAgent = "no";
          Compression = false;
          IdentityAgent = onePassPath;
          HashKnownHosts = true;
        };
      };
    };
  };
}
