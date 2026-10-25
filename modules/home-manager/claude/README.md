# Claude profiles

Enable `programs.claude.enable` to create an implicit `profiles.default` for
the regular `claude` command. Add named profiles for separate settings,
credentials, session history, and optional Linux desktop launchers.

```nix
programs.claude = {
  enable = true;
  profiles = {
    default.desktop.enable = true;
    work = {
      settings = {
        awsAuthRefresh = "aws sso login --sso-session Work";
        env = {
          CLAUDE_CODE_USE_BEDROCK = "1";
          AWS_REGION = "us-west-2";
          AWS_PROFILE = "work";
        };
      };
      desktop.enable = true;
    };
  };
};
```

The default CLI keeps `~/.claude`, the existing `~/.claude.json`, and its
existing login. Named profiles install `claude-<name>` and set
`CLAUDE_CONFIG_DIR` to `~/.claude-<name>`. The default wrapper unsets that
variable when using the standard directory: explicitly setting it, even to
`~/.claude`, would move the global `.claude.json` file into that directory.
Override `command`, `configDir`, `package`, `extraArgs`, or `extraPackages`
per profile. `finalPackage` exposes the generated CLI wrapper.

Desktop launchers are `claude-desktop` and `claude-desktop-<name>`. They set
the matching CLI config directory and tool PATH, and pass a separate Electron
`--user-data-dir`. The default app uses `~/.config/Claude`; other profiles use
`~/.config/Claude-<name>`. These paths follow Home Manager's XDG config
directory and can be changed with `desktop.userDataDir`. `desktop.settings`
manages mutable `claude_desktop_config.json` settings, including desktop MCP
servers. The app downloads and manages its own Claude Code binary; it shares
the profile's configuration rather than using `finalPackage` as its backend.
The stock app retains `com.anthropic.Claude` as its window identity, so windows
from both launchers share the upstream window grouping. Launcher filenames
are distinct and can be changed with `desktop.desktopId`.

For Bedrock profiles, `desktop.inferenceSettings` defaults to the CLI's
`settings.env` values for region, AWS profile, and Sonnet/Opus/Haiku models.
The module also supplies AWS CLI on PATH. Override `inferenceSettings` for
other providers or additional desktop options. Third-party desktop profiles
use a data directory ending in `-3p`, matching the pinned app's configuration
library. The module installs and selects a stable library entry while
preserving other saved entries. The app may still ask for consent to use
local AWS credentials. No credentials are copied into Nix-generated files.

Settings merge at activation and login. Declared leaves and arrays replace
their existing values; undeclared settings survive. `obsoleteSettings`
removes matching old managed leaves before merging, preserving leaves the
user has changed. `beforeLaunch`, `afterMerge`, and `activationScript` provide
hooks; activation scripts receive the profile's HOME and config directory.
Disable the implicit profile with `profiles.default.enable = false`.

The personal development module configures `default`; the Andromeda module
configures `andromeda`. Both retain the existing CLI arguments, tools, and
Herdr integration. During activation, matching legacy Bedrock settings are
removed from the shared default CLI settings, and the Andromeda CLI settings
are written to `~/.claude-andromeda/settings.json`. Existing histories and
credentials are left in place. Brick enables both desktop launchers.

Upstream references: [configuration directories and authentication](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts),
[desktop environment variables](https://code.claude.com/docs/en/desktop#environment-variables-in-local-sessions),
and [desktop inference configuration](https://claude.com/docs/third-party/claude-desktop/configuration).
