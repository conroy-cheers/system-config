# ChatGPT and Codex profiles

Enable `programs.chatgpt.enable` to create the `default` profile for the regular
`codex` command. `programs.chatgpt.profiles` is an attribute set of named
profiles. Each installs a Codex CLI wrapper and can install a ChatGPT desktop
launcher using the same `CODEX_HOME`, provider configuration, MCP servers, and
CLI wrapper.

```nix
programs.chatgpt.enable = true;
programs.chatgpt.profiles = {
  default = {
    settings.tui.pet = "rocky";
    desktop = {
      enable = true;
      webviewPort = 5175;
    };
  };
  work = {
    settings = {
      model_provider = "gateway";
      model_providers.gateway = {
        name = "Work gateway";
        base_url = "https://gateway.example/openai/v1";
        wire_api = "responses";
        auth = {
          command = "/run/current-system/sw/bin/cat";
          args = [ "/run/secrets/work-api-key" ];
          refresh_interval_ms = 0;
        };
      };
    };
    desktop = {
      enable = true;
      name = "ChatGPT Work";
      webviewPort = 5176;
    };
  };
};
```

The implicit `default` profile installs `codex` with `~/.codex`; other names
install `codex-<name>` with `~/.codex-<name>`. Override `command`, `codexHome`, or
`package` per setup. `extraPackages` adds tools to the standard CLI tool PATH;
`beforeLaunch` runs shell commands before CLI invocations. `finalPackage`
exposes the generated CLI wrapper for other modules. Set
`profiles.default.enable = false` to disable the default profile while keeping
other profiles enabled.

Desktop support uses the existing `codex-desktop-linux` input on Linux. Each
enabled desktop setup requires a unique `desktop.webviewPort`. Its command
and app ID default to `codex-desktop` or `codex-desktop-<name>`. The default
desktop retains `~/.config/Codex`; additional setups get separate Electron
profiles under `~/.config/codex-desktop-<name>`, so their desktop sign-ins and
app state are independent. These paths follow Home Manager's XDG config
directory. Override `desktop.userDataDir` to use an existing profile.

Managed TOML leaves merge into mutable `config.toml` during activation and at
login. Unmanaged settings and comments survive; arrays are replaced as a
whole. `removeSettings` takes paths such as `[ [ "mcp_servers" "old" ] ]` to
remove obsolete managed entries. `afterMerge` runs at both merge points;
`activationScript` runs only during Home Manager activation. Keep secrets in
runtime files and reference their paths instead of putting values in Nix.

The personal and Andromeda development modules configure `default` and
`andromeda`, preserving their existing provider/MCP settings, DeepSeek refresh,
Herdr integration, and CLI tools. Brick enables both desktop launchers. Usage
accounting discovers all enabled setups rather than hard-coding two homes.
