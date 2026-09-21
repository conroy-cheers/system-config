# Andromeda LLM gateway

`codex-andromeda` uses the Bifrost HTTPS Responses endpoint at
`https://llmgateway.tail738663.ts.net/openai/v1`, with WebSockets disabled.
The existing default remains GPT-5.6 Sol with high reasoning effort. Select
another permitted deployment with, for example:

```sh
codex-andromeda --model gpt-6-astra
```

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

The regular `codex` command retains its separate personal configuration.

Setup reference: [Andromeda gateway guide](https://andromeda-robotics.atlassian.net/wiki/x/L4AGUg).
