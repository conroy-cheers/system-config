# Andromeda LLM gateway

`codex-andromeda` uses a local CLIProxyAPI adapter by default. No `--profile`
flag is needed. Use `/model` to select and save a model and its reasoning
effort, or choose a deployment explicitly:

```sh
codex-andromeda --model gpt-6.1-sol
```

For example, to use DeepSeek:

```sh
codex-andromeda --model DeepSeek-V4.1-Flash
```

The adapter has two explicit model groups configured in the Andromeda module:

| Models | Bifrost route | Tool handling |
|---|---|---|
| GPT-6 Astra/Luna, GPT-6.1 Sol/Terra | `/openai/v1/responses` | Preserve native custom tools and low/medium/high/xhigh reasoning |
| DeepSeek-V4.1-Flash, Kimi-K3.1-Pro | `/openai/v1/chat/completions` | Convert custom tools to functions and restore Codex tool calls and history |

The second group advertises `none` and `high` reasoning, both accepted by the
gateway. Model aliases omit `azure/` in Codex; CLIProxyAPI restores
that provider prefix in requests to Bifrost. Adding a model requires assigning
it to the appropriate `relay.cliProxy.nativeModels` or `chatModels` list.
Live validation found intermittent Azure 404 errors for Kimi, including when
identical requests were sent directly to Bifrost without the local adapter.
Successful patch and tool continuations confirm conversion works, but Kimi's
upstream deployment needs repair before it can be considered reliable.
The existing `chat-completions` and `responses` profiles are aliases for the
same adapter, so either profile also supports both groups.

Every machine enabling the Andromeda Codex setup runs `cliproxyapi-andromeda`
as a user service. This overlay variant sets upstream `X-Request-Id` to
`00000000-0000-0000-0000-000000000000` after custom headers are applied, for
both native Responses and converted Chat Completions requests. Other instances
keep the standard package. Reusing this ID triggers Bifrost v2.0.0's billing
deduplication and log collisions, so its usage counters and request logs are
not reliable for this instance.
Codex sends Responses requests to
`http://127.0.0.1:4444/v1`; the adapter forwards to the normalized Bifrost base
`https://llmgateway.tail738663.ts.net/openai/v1`. No Azure passthrough is used.
The launcher reads the decrypted Bifrost key at startup into a private runtime
config, which is removed when the service stops. CLI and desktop launches need
no exported key. Hosted web search is disabled for this shared configuration.
On Linux, inspect or restart it with
`systemctl --user status codex-andromeda-relay` or
`systemctl --user restart codex-andromeda-relay`. On macOS the Home Manager
launchd agent is `org.nix-community.home.codex-andromeda-relay`.

The model catalog comes from CLIProxyAPI's local `/v1/models` endpoint with the
Codex client-version query. It contains exactly the configured model routes,
including native and bridged `apply_patch` support and reasoning levels. The
refresh helper validates it with the installed Codex binary before replacing
the cache; it does not copy the API key into the catalog.
Catalogs refresh at activation/login, periodically, and when stale before
launch. The cache is `~/.cache/codex-andromeda/relay/models.json`; a failed
refresh preserves the last successful catalog. The first launch needs the
local adapter running. Force a refresh with `codex-andromeda-relay-refresh`,
then start a new Codex client to see updates. On Linux, periodic refreshes use
the `codex-andromeda-relay-catalog` user service and timer; on macOS they use
the `org.nix-community.home.codex-andromeda-relay-catalog` launchd agent.

The Andromeda desktop launcher uses the same default relay configuration.
The relay reads the personal key at runtime from
`~/.agenix/agenix/andromeda.bifrost.key`; no shell export or Azure login is needed.
Connect to the office network or Andromeda Tailscale network first.

The source secret is `secrets/master/andromeda/bifrost/key.age`. It is managed by
ragenix/agenix-rekey and rekeyed for each host enabling
`andromeda.development`. To rotate it, use `nix develop`, then
`agenix edit secrets/master/andromeda/bifrost/key.age` and `agenix rekey -a` before
rebuilding the affected machines. Keep any temporary plaintext key files out
of Git and remove them after confirming the deployed secret works.
Restart the relay after rotating its key.

The regular `codex` command retains its separate personal configuration.

Setup reference: [Andromeda gateway guide](https://andromeda-robotics.atlassian.net/wiki/x/L4AGUg).
