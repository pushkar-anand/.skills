---
name: 1pass-read
description: Discover and read stored website accounts in 1Password — list every account the agent holds, find one by domain or URL, reveal a username, password or recovery codes, and get a live 6-digit 2FA/TOTP code. Use when signing in to a site, filling a login form, completing a two-factor prompt, or checking what accounts already exist before signing up. Reads only; never modifies the vault.
compatibility: Requires curl and jq, and a 1Password Connect server reachable through OP_CONNECT_HOST and OP_CONNECT_TOKEN.
metadata:
  author: pushkar-anand
  version: "1.0"
---

# Read website accounts from 1Password

Read-only access to the accounts stored in this agent's own vault. Every command
here is safe to run: nothing writes. Creating accounts lives in `1pass-create`,
2FA setup in `1pass-2fa`.

## Files

`scripts/find.sh`, `scripts/show.sh`, `scripts/totp.sh`, `scripts/run.sh` and
`scripts/vault.sh` are the commands. `scripts/lib.sh` is sourced by every one of
them and is never run directly — but it must be present, or they all fail on
their first line.

## Which vault

Every agent holds a Connect token scoped to its own vault, so there is normally
exactly one vault to reach and nothing to choose. The scripts here work that out
themselves — none of them take a vault argument.

If the token can reach more than one, the scripts stop and ask rather than guess,
because writing an account into the wrong vault puts it where another agent can
read it. Set `OP_VAULT` (name or UUID) to settle it.

An `op://` reference is the one place the vault has to be named literally:

```bash
scripts/vault.sh                                  # -> agent-<name>
op read "op://$(scripts/vault.sh)/github.com/password"
```

`find.sh` also prints the full reference for each item, so it is usually already
on screen.

## Before anything else: find the item

The agent normally starts from a URL, not an item name. Resolve it first:

```bash
scripts/find.sh github.com
```

This prints the item id, username, saved URLs and whether 2FA is stored — no
secrets — so it is safe to run freely and safe to leave in a log.

If it prints nothing, no account exists yet. Signing up is `1pass-create`'s job;
do not invent credentials and do not reuse another site's.

With no argument it lists every account in the vault, which answers "what do I
already have?" before deciding to register anywhere:

```bash
scripts/find.sh
```

Every other script takes either the item id or any text that matches exactly one
item. An ambiguous match is refused rather than guessed — signing in with the
wrong account is worse than stopping to ask.

## Logging in

Pipe the password straight into whatever consumes it — it never enters the
conversation this way:

```bash
scripts/show.sh github.com username
scripts/show.sh github.com password --exec <command>
```

Without `--exec` the value is printed, which puts it in the transcript for good;
the script warns when it does. Only do that when the model itself has to type it
into a form on screen. See the rules below.

One field per call, named explicitly. There is deliberately no "dump the whole
item" command: that would put every secret on the item into the transcript when
only one was needed.

## Two-factor prompts

```bash
scripts/totp.sh github.com     # -> 452 981
```

Prints the current code and nothing else, so it can be piped straight into a form
fill. 1Password derives the code server-side from the stored seed, so there is no
TOTP implementation and no clock of ours involved.

Codes expire every 30 seconds. Fetch one when the prompt is actually on screen,
not at the start of the login. If the site rejects a code, fetch a fresh one
before assuming the seed is wrong.

If a site asks for a recovery code instead:

```bash
scripts/show.sh github.com 'recovery codes'
```

## Never put a credential in the transcript

Anything printed here lands in the terminal transcript, the conversation, and the
gateway logs, and stays there long after the task is done. Treat that as the
thing to avoid, not as a cost of doing business.

**Do not** print a password, recovery code or TOTP seed unless the model itself
has to type it into a form on screen. **Never** repeat one back afterwards — not
in a summary, an explanation, a status message, a commit message, or a reply to
the user. If asked what a password is, say where it is stored instead of
printing it.

Send the value where it needs to go instead of printing it. Whenever the consumer
is a program rather than a form on screen, there are three routes — all keep the
secret out of the conversation, so pick whichever fits.

**`op read`** — fewest moving parts, no script involved. Best when the vault name
and item title are already known and one secret is needed. A command substitution
captures it without it ever reaching stdout:

```bash
PASSWORD=$(op read "op://<vault>/github.com/password")
CODE=$(op read "op://<vault>/github.com/one-time password?attribute=otp")
```

`find.sh` prints the exact `op://` reference for every item, so it is usually a
copy away. `op read` works against a Connect server with no setup beyond the
`OP_CONNECT_*` variables already in the environment, and `op inject` covers a
template file needing several secrets at once.

**`run.sh`** — better when the item has to be found by domain rather than named
exactly, when the vault name is not to hand, when several fields are needed in
one go, or for a live code without the `?attribute=otp` syntax:

```bash
scripts/run.sh github.com GH_USER=username GH_TOKEN=password -- ./deploy.sh
scripts/run.sh github.com CODE=totp -- ./login.sh
```

**`show.sh --exec`** — when the consumer reads the value on stdin rather than
from the environment:

```bash
scripts/show.sh github.com password --exec <command>
```

Whichever route: the secret must not be echoed, and `$VAR` must not be expanded
into a message. When printing really is unavoidable:

- Read the value at the moment it is used, never in advance.
- Read one field, not the whole item.
- Say "entered the stored password", not the password.

TOTP codes are the mild case: single-use and dead in 30 seconds, so `totp.sh`
printing one is low risk. The seed behind it is not — that is a permanent
credential, and only `1pass-2fa` handles it.

## When something is missing

| Symptom | Cause |
|---|---|
| `no item matches` | No account stored yet — see `1pass-create` |
| `'x' matches N items` | Re-run with the exact title or the item id it lists |
| `no 2FA stored` | The account has no seed — see `1pass-2fa` |
| `this token reaches no vaults` | The Connect server has not been granted this agent's vault |
| `cannot reach Connect` | The Connect server is down, or `OP_CONNECT_HOST` is wrong |
