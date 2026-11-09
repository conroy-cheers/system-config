# Andromeda LLM gateway

`codex-andromeda` uses the Bifrost Azure passthrough HTTPS Responses endpoint at
`https://llmgateway.tail738663.ts.net/azure_passthrough/openai/v1`, with WebSockets disabled.
The existing default remains GPT-5.6 Sol with high reasoning effort. Select
another permitted deployment with, for example:

```sh
codex-andromeda --model gpt-6-astra
```

For models that expose Chat Completions, select the relay profile:

```sh
codex-andromeda --profile chat-completions --model DeepSeek-V4.1-Flash
```

Every machine enabling the Andromeda Codex setup also runs nixpkgs'
`codex-relay` as a user service. Codex sends Responses requests to
`http://127.0.0.1:4444/v1`; the relay translates them to Chat Completions at
`https://llmgateway.tail738663.ts.net/azure_passthrough/openai/v1/`.
The relay reads the same decrypted Bifrost key when it starts, so CLI and
desktop launches need no exported key. The `chat-completions` profile disables
hosted web search. Select the upstream deployment explicitly with `--model`.
On Linux, inspect or restart it with
`systemctl --user status codex-andromeda-relay` or
`systemctl --user restart codex-andromeda-relay`. On macOS the Home Manager
launchd agent is `org.nix-community.home.codex-andromeda-relay`.

The relay profile gets its model catalog from the gateway's
`https://llmgateway.tail738663.ts.net/openai/v1/models` endpoint using the same
Bifrost key. Discovery is separate from the Azure passthrough inference URL.
Only `azure/` model IDs are included, and that prefix is removed for inference,
so `azure/DeepSeek-V4.1-Flash` appears as `DeepSeek-V4.1-Flash` in the picker.
Catalogs refresh at activation/login, periodically, and when stale before
launch. The cache is `~/.cache/codex-andromeda/relay/models.json`; a failed
refresh preserves the last successful catalog. The first relay-profile launch
needs gateway access. Force a refresh with `codex-andromeda-relay-refresh`,
then start a new Codex client to see updates. On Linux, periodic refreshes use
the `codex-andromeda-relay-catalog` user service and timer; on macOS they use
the `org.nix-community.home.codex-andromeda-relay-catalog` launchd agent.

The Andromeda desktop launcher uses the same configuration. Codex reads the
personal key at runtime from `~/.agenix/agenix/andromeda.bifrost.key` using its
provider authentication command; no shell export or Azure login is needed.
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
