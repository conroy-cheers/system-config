# DeepSeek in corncheese Codex

Run `codex --profile deepseek`, or select Pro with
`codex --profile deepseek --model deepseek-v4-pro`. Noninteractive use is
`codex exec --profile deepseek "review this change"`.

Home Manager registers the provider in the existing merged `~/.codex/config.toml`
and installs `~/.codex/deepseek.config.toml`. The provider's authentication command
reads `age.secrets."corncheese.deepseek.key".path` at runtime. The existing default
provider and ChatGPT authentication are preserved.

## Catalog refresh

The corncheese wrapper refreshes the catalog before a DeepSeek profile launch
when it is older than 24 hours. `codex-deepseek-refresh` forces an immediate
refresh; `--if-stale` respects the cache age. Both update the catalog for the next
Codex process, not sessions already running. Activation seeds the bundled
fallback without accessing the network.

The cache is `${xdg.cacheHome}/codex/deepseek/models.json` (normally
`~/.cache/codex/deepseek/models.json`). A file lock serializes concurrent launches,
and replacements are atomic. Downloads have a five-second deadline. Failed
downloads or incompatible metadata retain the last valid catalog, or the bundled
fallback on first use. Automatic retries back off for five minutes; manual
refreshes report failure with a nonzero exit status.

DeepSeek's `/models` API lacks Codex capability metadata. The refresher downloads
the official installer below and extracts its `CODEX_MODELS_JSON` heredoc as data;
it never executes or sources the downloaded script. An installer format change,
invalid catalog, missing default model, or newer minimum client version causes a
refresh failure and preserves the cache.

Only an explicit set of model capability fields can update remotely. The pinned
instructions are reapplied to cached and downloaded models on each DeepSeek
launch. Newly published models inherit the same local instructions. New metadata
fields require a code review before the refresher will use them.

## Bundled snapshot

`deepseek-models.json` and `deepseek-instructions.txt` were extracted on
2026-09-18 from:

https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh

Integration guide:
https://api-docs.deepseek.com/quick_start/agent_integrations/codex/

The two published models have identical `base_instructions` and
`model_messages.instructions_template`. Those instructions are stored once,
verbatim, in `deepseek-instructions.txt`; the generated catalog uses them as
`model_messages.instructions_template`. Updating this prompt requires a reviewed
repository change, independently of runtime capability refreshes.

Tests: `python3 modules/home-manager/corncheese-development/test_deepseek_refresh.py`.
