---
name: 1pass-create
description: Create and update website accounts in 1Password when signing up for a new service — generate a strong password, store it as a login item with the site URL and username, rotate a password later, and save extra details like security answers or an account number. Use when registering for a website, creating an account, or changing a stored password. Writes to the vault; pair with 1pass-2fa to enable two-factor on the new account.
compatibility: Requires curl and jq, and a 1Password Connect server reachable through OP_CONNECT_HOST and OP_CONNECT_TOKEN with write access to the agent's vault.
metadata:
  author: pushkar-anand
  version: "1.0"
---

# Create website accounts in 1Password

Used when the agent signs up for a service and needs somewhere to put the
credentials. Looking accounts up again is `1pass-read`; two-factor setup is
`1pass-2fa`.

## Check the token can write, once

```bash
scripts/preflight.sh
```

Connect tokens carry per-vault read/write scopes fixed when the token is issued,
and a read-only token fails only at the moment of writing. Run this before the
first signup rather than discovering the problem with the site's one-time 2FA
seed already on screen. It creates a probe item carrying no secret and deletes it
again.

If it reports `Write: DENIED`, stop. Issue a new Connect token with write access
to this agent's vault and replace `OP_CONNECT_TOKEN` in the profile's `.env` —
there is no way to work around it from here.

## The signup order that matters

Create the item **before** submitting the signup form, not after. If the form
succeeds and the store fails, the account exists with a password nobody holds.

```bash
scripts/create.sh github.com me@example.com
```

That generates the password inside 1Password — server-side, from a recipe —
rather than having the agent invent one. It is not printed: it exists in the
vault, and gets piped to whatever needs it. Defaults to 32 characters of letters,
digits and symbols.

For sites that reject symbols or cap length, say so up front instead of letting
the form bounce:

```bash
scripts/create.sh example.com me@example.com --no-symbols --length 16
```

Other options: `--url` when the sign-in page differs from the bare domain,
`--title` when one domain holds several accounts, `--force` to add a second
account for a domain that already has one, and `--reveal` — which prints the
password, so read the rules below before reaching for it.

`create.sh` refuses by default if an account for that domain already exists, and
prints what it found. That is usually the signal to log in with `1pass-read`
rather than to sign up again.

## After the form is submitted

1. If the site offers two-factor, enable it now and store the seed with
   `1pass-2fa`. Doing it later means a second sign-in, and some sites only offer
   the option during onboarding.
2. If the site issued anything else once — an account number, a security
   question, an API key — put it on the same item:

```bash
scripts/set-field.sh github.com 'security answer' concealed 'first pet'
scripts/set-field.sh github.com 'account number' string 4417-9920
```

## Rotating a password

Same script, targeting the password field, so the value is replaced rather than a
second password field appended:

```bash
printf '%s' "$new" | scripts/set-field.sh github.com password concealed -
```

Store the new password **before** submitting the change form, for the same reason
as signup. If the site generates the new password rather than accepting one,
submit first and store immediately after, in the same run.

## Never put a credential in the transcript

`create.sh` does **not** print the generated password. The account is fully
usable without ever revealing it: the password is in the vault before the script
returns, and a command substitution puts it in a variable without it ever
reaching stdout.

```bash
PASSWORD=$(op read "op://<vault>/github.com/password")
```

`create.sh` prints that exact reference on success, so it can be copied straight
into the next command.

Pass `--reveal` only when the model itself has to type the password into a form
on screen. Everything printed goes into the transcript, the conversation and the
gateway logs, and outlives the task there.

**Never** repeat a password back afterwards — not in a summary, a status
message, a commit message, or a reply to the user. Say "signed up and stored the
credentials in 1Password", never the value. If asked for a password, say where it
is stored.

Prefer `-` and stdin over putting a secret in the command line: arguments are
readable from `/proc` for the life of the process, and land in shell history.

## Conventions worth keeping

- **One item per account**, titled with the bare domain (`github.com`), so
  `1pass-read`'s lookup finds it from a URL.
- **Never reuse a password** across sites. Every `create.sh` call generates a new
  one; there is no reason to copy an existing value.
- **Never invent a password** in the agent's own text. Model-written passwords
  are weaker than they look, and the generated one is already in the vault before
  it is displayed.
