# nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in
#   import ./modules/home-manager/chatgpt/tests.nix {
#     inherit (f) inputs; pkgs = f.nixosConfigurations.kombu.pkgs;
#   }'
{ inputs, pkgs }:
let
  lib = pkgs.lib.extend (_: _: { hm = inputs.home-manager.lib.hm; });
  merger = import ./config-merge.nix { inherit lib pkgs; };
  cli =
    p:
    (p.writeShellScriptBin "codex" ''printf '%s\n' "$CODEX_HOME" "$@"'').overrideAttrs {
      version = "0.169.0";
    };
  desktop = pkgs.runCommand "test-codex-desktop" { } ''
    mkdir -p "$out/bin" "$out/share/icons/hicolor"
    ln -s ${pkgs.coreutils}/bin/true "$out/bin/codex-desktop"
  '';
  home =
    p: extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = p;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ./default.nix
        {
          manual.manpages.enable = false;
          home = {
            username = "tester";
            homeDirectory = "/chatgpt-test-home";
            stateVersion = "24.05";
          };
          programs.chatgpt = {
            enable = true;
            profiles.default.package = cli p;
          };
        }
        extra
      ];
    };
  plugin =
    version:
    pkgs.runCommand "fixture-plugin-${version}" { } ''
        mkdir -p "$out/.codex-plugin" "$out/skills/fixture-skill"
      sed 's/name: fixture-skill/name: fixture-plugin-skill/' ${./test-fixtures/SKILL.md} > "$out/skills/fixture-skill/SKILL.md"
        echo '{"name":"fixture-plugin","version":"${version}","skills":"./skills"}' > "$out/.codex-plugin/plugin.json"
    '';
  workHooks = pkgs.runCommand "work-hooks" { } ''
    mkdir -p "$out"
    echo '{"hooks":{}}' > "$out/hooks.json"
    touch "$out/helper.sh"
  '';
  workSkills = pkgs.runCommand "work-skills" { } ''
    mkdir -p "$out"
    cp ${./test-fixtures/SKILL.md} "$out/fixture-skill.md"
  '';
  linux = home pkgs {
    programs.mcp = {
      enable = true;
      servers.shared.command = "fixture-mcp";
    };
    programs.chatgpt.profiles = {
      default = {
        enableMcpIntegration = true;
        settings.model = "default-model";
        context = "Default global instructions";
        contextOverride = "Default override instructions";
        skills.fixture-skill = ./test-fixtures/SKILL.md;
        rules.fixture = ''prefix_rule(pattern = ["git", "status"], decision = "allow")'';
        hooks.SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = "true";
              }
            ];
          }
        ];
        plugins = [ (plugin "1.0.0") ];
        configProfiles.native.settings.model = "default-profile-model";
        configProfiles.managed.settings.model_provider = "relay";
        afterMerge = "touch /chatgpt-test-home/after-merge-ran";
        activationScript = "touch /chatgpt-test-home/activation-hook-ran";
      };
      work = {
        package = cli pkgs;
        settings.model = "work-model";
        enableMcpIntegration = true;
        context = ./test-fixtures/context.md;
        contextOverride = "Work override instructions";
        skills = workSkills;
        rules.fixture = ''prefix_rule(pattern = ["git", "diff"], decision = "allow")'';
        hooks = workHooks;
        plugins = [ (plugin "2.0.0") ];
        configProfiles.native.settings.model = "work-profile-model";
        relay = {
          enable = true;
          upstream = "https://example.invalid/v1";
          catalog.enable = false;
        };
        desktop = {
          enable = true;
          package = desktop;
          webviewPort = 5176;
        };
      };
    };
  };
  xdg = home pkgs {
    home.preferXdgDirectories = true;
    programs.chatgpt.profiles.default.context = "XDG context";
  };
  customHome = home pkgs {
    programs.chatgpt.profiles.default.codexHome = "/chatgpt-test-home/custom-codex";
    programs.chatgpt.profiles.default.context = "Custom home context";
  };
  namedOnly = home pkgs {
    programs.chatgpt.profiles = {
      default.enable = false;
      work = {
        package = cli pkgs;
        settings.model = "work-model";
        context = "Named-only context";
      };
    };
  };
  disabled = home pkgs { programs.chatgpt.enable = lib.mkForce false; };
  darwin = home (import inputs.nixpkgs { system = "aarch64-darwin"; }) {
    programs.chatgpt.profiles.default.context = "Darwin context";
    programs.chatgpt.profiles.default.relay = {
      enable = true;
      upstream = "https://example.invalid/v1";
      catalog.enable = false;
    };
  };
  c = linux.config;
  template = pkgs.writeText "codex-merge-test.sh" (
    merger.merge {
      source = "/CODEX_TEST_SOURCE";
      target = "/CODEX_TEST_TARGET";
      removeSettings = [ [ "model_catalog_json" ] ];
    }
  );
  storeConfig = pkgs.writeText "old-codex-config.toml" ''
    model_provider = "relay"
    web_search = "disabled"
    [model_providers.relay]
    name = "Test relay"
    wire_api = "responses"
  '';
  activation = pkgs.writeText "chatgpt-test-activation.sh" (
    ''
      errorEcho() { echo "$@" >&2; }
    ''
    + lib.concatMapStringsSep "\n" (name: c.home.activation.${name}.data) [
      "mergeCodexSetup-default"
      "mergeCodexSetup-work"
    ]
  );
in
assert !c.programs.codex.enable;
assert c.home.file."/chatgpt-test-home/.codex/AGENTS.md".enable;
assert c.home.file."/chatgpt-test-home/.codex-work/AGENTS.md".enable;
assert !(c.home.activation ? codexMutableSettings);
assert c.programs.chatgpt.profiles.work.codexHome == "/chatgpt-test-home/.codex-work";
assert c.xdg.desktopEntries.codex-desktop-work.settings.StartupWMClass == "codex-desktop-work";
assert c.systemd.user.services ? codex-work-relay;
assert !(c.systemd.user.services ? codex-config-merge);
assert xdg.config.programs.chatgpt.profiles.default.codexHome == "/chatgpt-test-home/.config/codex";
assert xdg.config.home.file."/chatgpt-test-home/.config/codex/AGENTS.md".enable;
assert !customHome.config.programs.codex.enable;
assert customHome.config.home.file."/chatgpt-test-home/custom-codex/AGENTS.md".enable;
assert customHome.config.home.activation ? mergeCodexSetup-default;
assert !namedOnly.config.programs.codex.enable;
assert namedOnly.config.home.file."/chatgpt-test-home/.codex-work/AGENTS.md".enable;
assert namedOnly.config.home.activation ? mergeCodexSetup-work;
assert !disabled.config.programs.codex.enable;
assert !(disabled.config.home.activation ? mergeCodexSetup-default);
assert darwin.config.launchd.agents ? codex-relay;
assert !(darwin.config.launchd.agents ? codex-config-merge);
assert builtins.all (h: builtins.isString h.activationPackage.drvPath) [
  linux
  xdg
  customHome
  namedOnly
  disabled
  darwin
];
pkgs.runCommand "chatgpt-module-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.bash
    ];
    CODEX_PROFILE_TEST_MERGER = template;
    CODEX_PROFILE_TEST_STORE_CONFIG = storeConfig;
    CODEX_PROFILE_TEST_CODEX =
      lib.getExe' inputs.codex-flake.packages.${pkgs.stdenv.hostPlatform.system}.codex
        "codex";
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python ${./test_config_profiles.py} -v
    test_home="$TMPDIR/test-home"
    substitute ${activation} activation.sh --replace-fail /chatgpt-test-home "$test_home"
    mkdir -p "$test_home/.codex"
    cp -rL ${linux.activationPackage}/home-files/. "$test_home/"
    chmod -R u+w "$test_home"
    printf '%s\n' 'model = "user-choice"' 'model_reasoning_effort = "high"' > "$test_home/.codex/config.toml"
    ln -s ${storeConfig} "$test_home/.codex/native.config.toml"
    DRY_RUN=1 bash -e activation.sh
    test ! -e "$test_home/after-merge-ran"
    test ! -e "$test_home/activation-hook-ran"
    test -L "$test_home/.codex/native.config.toml"
    bash -e activation.sh
    test -e "$test_home/after-merge-ran"
    test -e "$test_home/activation-hook-ran"
    test ! -L "$test_home/.codex/native.config.toml"
    ${lib.getExe pkgs.jaq} --from toml -e '
      .model == "default-model" and .model_reasoning_effort == "high"
      and .mcp_servers.shared.command == "fixture-mcp"
    ' "$test_home/.codex/config.toml"
    ${lib.getExe pkgs.jaq} --from toml -e '.model == "default-profile-model"' "$test_home/.codex/native.config.toml"
    ${lib.getExe pkgs.jaq} --from toml -e '.model == "work-model"' "$test_home/.codex-work/config.toml"
    ${lib.getExe pkgs.jaq} --from toml -e '.model == "work-profile-model" and .model_provider == null' "$test_home/.codex-work/native.config.toml"
    grep -q 'Default global instructions' "$test_home/.codex/AGENTS.md"
    grep -q "work instance" "$test_home/.codex-work/AGENTS.md"
    grep -q 'Default override' "$test_home/.codex/AGENTS.override.md"
    grep -q 'Work override' "$test_home/.codex-work/AGENTS.override.md"
    test -f "$test_home/.codex/skills/fixture-skill/SKILL.md"
    test -f "$test_home/.codex-work/skills/fixture-skill.md/SKILL.md"
    test -f "$test_home/.codex/hooks.json"
    test -f "$test_home/.codex-work/hooks.json"
    test -f "$test_home/.codex-work/hooks/helper.sh"
    for instance in .codex .codex-work; do
      ${lib.getExe pkgs.jaq} --from toml -e '.plugins["fixture-plugin@home-manager"].enabled' "$test_home/$instance/config.toml"
    done
    test -f "$test_home/.codex/plugins/cache/home-manager/fixture-plugin/1.0.0/.codex-plugin/plugin.json"
    test -f "$test_home/.codex-work/plugins/cache/home-manager/fixture-plugin/2.0.0/.codex-plugin/plugin.json"
    CODEX_INSTANCE_TEST_ROOT="$test_home" python ${./test_instances.py} -v
    substitute ${lib.getExe c.programs.chatgpt.profiles.default.finalPackage} default.sh \
      --replace-fail /chatgpt-test-home "$TMPDIR/test-home"
    substitute ${lib.getExe c.programs.chatgpt.profiles.work.finalPackage} work.sh \
      --replace-fail /chatgpt-test-home "$TMPDIR/test-home"
    bash default.sh hello > default.txt
    bash work.sh hello > work.txt
    test "$(head -n1 default.txt)" = "$TMPDIR/test-home/.codex"
    test "$(head -n1 work.txt)" = "$TMPDIR/test-home/.codex-work"
    test "$(tail -n1 work.txt)" = hello
    touch "$out"
  ''
