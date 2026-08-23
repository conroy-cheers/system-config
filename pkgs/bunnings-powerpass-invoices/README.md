# Bunnings PowerPass invoices

Downloads one tax-invoice PDF per transaction from the authenticated PowerPass
portal. The tool does not export cookies to a file. It uses its own persistent
Chromium profile or attaches to an explicitly configured Chromium DevTools
endpoint. Local interactive use can renew authentication with the Bunnings
login in 1Password item `o4mapnpvcr5cvwx4u5qjhwy62a`.

## Usage

Check or renew authentication headlessly:

```console
nix run .#bunnings-powerpass-invoices -- auth-check
```

Then fetch the current month's invoices:

```console
nix run .#bunnings-powerpass-invoices -- fetch -o ./invoices
```

Or select a date range:

```console
nix run .#bunnings-powerpass-invoices -- fetch \
  --from 01/07/2026 --to 31/07/2026 -o ./invoices
```

Use `fetch --dry-run` to list matched invoices first. Existing PDFs are skipped
unless `--force` is supplied.

The normal local renewal order is:

1. Reuse the current PowerPass APEX session.
2. Silently create a new APEX session through the remembered Bunnings/Okta SSO
   session.
3. If necessary, read the username and password from 1Password in memory, submit
   the Bunnings Trade sign-in form, and select **Remember me**.
4. Fail with an explicit interaction-required error if the identity provider
   presents MFA, CAPTCHA, or another unknown challenge.

Bunnings currently requires a six-digit code delivered through an enrolled SMS
or email factor after a fresh profile submits its password. Bootstrap the
managed profile once with `login`; the tool fills the 1Password credentials,
selects **Trust this device**, and waits for the operator to enter that code.
Normal session expiry should then renew headlessly from the trusted-device and
remembered-SSO cookies. A later risk-based challenge will require the same
one-time recovery again.

The tool first uses `/run/wrappers/bin/op` so desktop-app integration works, then
falls back to an `op` executable in `PATH`. The host or service configuration is
responsible for installing the unfree 1Password CLI. The current Private-vault
item requires the local 1Password desktop app to be unlocked. Neither
credentials nor `op` output are logged.

Use the visible browser only to recover from an interactive challenge:

```console
nix run .#bunnings-powerpass-invoices -- login
```

## Headless service on sleet

The NixOS service exposes this stdio backend through an OAuth-protected
Streamable HTTP gateway. The MCP backend is deliberately session-only: it has
no 1Password access and does not expose password or MFA tools. Its tools are:

- `authentication_status`, which reports whether the retained trusted session
  is usable;
- `list_invoices`, which returns transaction metadata and a
  `powerpass://invoice/...` URI for each matching invoice; and
- the `powerpass://invoice/{invoice_id}` resource template, which returns the
  selected invoice as an `application/pdf` binary resource.

Bootstrap or renew the service profile from an SSH terminal on `sleet`:

```console
ssh sleet
sudo bunnings-powerpass-invoices-login
```

The service keeps a dedicated headless Chromium process alive and exposes its
DevTools endpoint on loopback only. The helper pauses MCP requests, attaches to
that browser as the service account, and prompts for a password and SMS code
only if Bunnings requires them. Both are read without terminal echo. It selects
**Remember me** and **Trust this device**, then restarts the MCP gateway without
closing Chromium. The retained profile lives in
`/var/lib/bunnings-powerpass-invoices/chromium` with mode `0700`.

Trusted-device state is not permanent. If Bunnings expires or revokes it, MCP
calls return `authentication_required`; repeat the SSH command. Passwords and
SMS codes never pass through MCP, its HTTP gateway, its process environment, or
its logs.

For local non-service debugging, `auth-session` still implements a
single-process stdin exchange, while `login-cli` uses non-echoing terminal
prompts throughout.

To use another already-running automation-specific Chromium profile, start
Chromium with a DevTools port and pass it with `--cdp-url`, for example:

```console
bunnings-powerpass-invoices --cdp-url http://127.0.0.1:9222 fetch -o ./invoices
```

Do not point two Chromium processes at the same profile. The default profile is
kept under `$XDG_STATE_HOME/bunnings-powerpass-invoices/chromium` (or
`~/.local/state/bunnings-powerpass-invoices/chromium`).

## Portal behaviour observed

- The portal is an Oracle APEX application.
- Authentication is an OIDC authorization-code flow through Bunnings'
  authorization service and an Okta-hosted commercial login.
- Each rendered transaction number is a session-bound, checksum-protected
  `PRINT_SINGLE` URL that returns `transaction_report.pdf`.
- A downloaded single-transaction report is a normal PDF produced by Oracle
  Analytics Publisher.
- The portal also exposes a `BTC_Tax_Invoice_Multi` report with a 50-transaction
  selection limit, but individual requests avoid having to split multi-page
  invoice reports.
- The search UI documents a maximum of 500 returned transactions. Use narrower
  date ranges if an account can exceed that limit.

Invoice requests are deliberately sequential because they share Oracle APEX
session state.
