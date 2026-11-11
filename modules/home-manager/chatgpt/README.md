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

`configProfiles.<name>.settings` manages a named Codex profile's settings in
`$CODEX_HOME/<name>.config.toml`. These files are writable and merged at
activation and login, like the base config. Unmanaged leaves, including a
model selected in the TUI, survive later merges. Existing Home Manager
symlinks are migrated to private regular files after file activation.
Use `configProfiles.<name>.removeSettings` for obsolete managed paths, just as
with the base config's `removeSettings` option.

Enable `relay.enable` on a setup to install `pkgs.codex-relay` and run a
loopback-only user service (`<command>-relay` under systemd on Linux or launchd
on macOS). Set `relay.upstream` to a Chat Completions API base URL and
`relay.apiKeyFile` to an optional runtime bearer-token file. The token is read
when the service starts; restart the service after rotating it. Set a distinct
`relay.port` for each enabled relay; the default is 4444. `relay.package` can
override the nixpkgs package.

For gateways with a mix of native Responses and function-only models, select
`relay.backend = "cliproxyapi"`. The shared module uses `pkgs.cliproxyapi`,
binds it to the same loopback port, and renders its upstream key into a private
runtime config. The key stays outside the Nix store and the config is removed
when the service stops. OAuth, the management dashboard, and hosted image-tool
injection are not enabled by this setup.

```nix
programs.chatgpt.profiles.work.relay = {
  enable = true;
  makeDefault = true;
  backend = "cliproxyapi";
  upstream = "https://gateway.example/openai/v1";
  apiKeyFile = "/run/secrets/gateway-key";
  cliProxy = {
    nativeModels = [{
      name = "azure/gpt-6.1-sol";
      alias = "gpt-6.1-sol";
      thinking.levels = [ "low" "medium" "high" "xhigh" ];
    }];
    chatModels = [{
      name = "azure/DeepSeek-V4.1-Flash";
      alias = "DeepSeek-V4.1-Flash";
      thinking.levels = [ "none" "high" ];
    }];
  };
};
```

Native models use the upstream `/responses` endpoint and preserve custom tools.
Chat models use `/chat/completions`; CLIProxyAPI converts custom tools to
functions and restores the response and history Codex expects. Model mappings
are explicit, not detected from inference failures. Their aliases are the
model IDs shown in Codex. `relay.launcher` exposes the generated runtime launcher.
For this backend the catalog refresh helper reads CLIProxyAPI's local Codex
catalog, including its model-specific tool and reasoning capabilities, and
validates it with the setup's Codex package. The service must be running before
the first catalog refresh. Linux refresh units depend on the adapter service.

The relay adds a `relay` Responses provider to the setup's merged TOML and
merges `$CODEX_HOME/chat-completions.config.toml` as a writable profile. Use
`codex-work --profile chat-completions --model <upstream-model>` to opt in.
This profile disables hosted web search, which the relay cannot translate.
Set `relay.makeDefault = true` to use these settings in the base config too,
so plain CLI and desktop launches use the relay and catalog without selecting
a profile. CLI and desktop share the same background relay; no shell
environment is required.

Relay catalogs are enabled by default. With the `codex-relay` backend it generates
metadata using the setup's unwrapped Codex package, and the refresh helper
keeps only the models advertised by the discovery API. The result is validated
by that Codex version and atomically cached at
`$XDG_CACHE_HOME/<command>/relay/models.json`. The `chat-completions` profile
sets `model_catalog_json`; enabling `relay.makeDefault` also sets it in the
base config.

For `codex-relay`, configure a separate discovery API or model-name prefix when needed:

```nix
programs.chatgpt.profiles.work.relay.catalog = {
  upstream = "https://gateway.example/openai/v1/"; # /models is appended
  stripPrefix = "azure/"; # select matching IDs and remove the prefix
  overrides."example-model".context_window = 131072;
};
```

`catalog.upstream` defaults to `relay.upstream`, and discovery uses the same
runtime bearer-token file. Metadata comes from the relay's heuristics and the
installed Codex's bundled instructions/tool formats. Models matching a bundled
Codex model after prefix removal also retain its reasoning levels and default.
Set `catalog.reasoningEfforts` to restrict those levels to efforts accepted by
the gateway (for example, `[ "low" "medium" "high" "xhigh" ]`); the default
`null` preserves all levels. Unknown models keep the relay's capabilities.
Use `catalog.overrides`
for known model capabilities, and `catalog.modelTemplate` to choose a different
bundled template. Override keys are normalized model IDs; `slug` cannot be
overridden.

Refreshes run at activation/login and periodically using a systemd user timer
or launchd agent named `<command>-relay-catalog`. CLI launches with
`--profile chat-completions`, launches using the relay by default, and desktop
launches also check freshness. The
default maximum age is 24 hours (`catalog.refreshInterval`, in seconds).
Periodic checks run at least hourly; failed attempts have a five-minute retry
backoff. The last successful catalog remains usable when the gateway is
unreachable. The first relay-profile launch needs gateway access if no catalog
has been cached yet. Activation and native-provider desktop startup can proceed
without one. Run `<command>-relay-refresh` to force a refresh, or add
`--if-stale` to respect the cache. Restart an existing client to load updates.

Set `catalog.enable = false` to opt out, or `catalog.cacheFile` to use another
absolute path. `catalog.refreshPackage` exposes the generated command for other
modules. No authenticated fetching happens during Nix evaluation or builds.

`test_relay_catalog.py` exercises generation, filtering, validation, failures,
and concurrent refreshes against a local API. Set `CODEX_RELAY_TEST_CODEX` and
`CODEX_RELAY_TEST_RELAY` to the unwrapped binaries and run it with Python 3.11
or newer; no inference requests are needed.
`test_config_profiles.py` checks symlink migration, model persistence through
Codex's `config/batchWrite` API, and preservation across later merges. Run it
with `tomlkit` available and `CODEX_PROFILE_TEST_CODEX` pointing to the binary.
`test_cliproxyapi.py` runs the real packaged adapter against a local upstream,
checking native tool/effort preservation, custom-tool conversion and streaming,
history replay, private credential cleanup, and catalog validation. Set
`CODEX_CLIPROXY_TEST_PROGRAM` and `CODEX_RELAY_TEST_CODEX` to the binaries;
these tests do not call a real model.

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
