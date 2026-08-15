---
name: 1pass-2fa
description: Turn on two-factor authentication for a website account and store its TOTP seed and recovery codes in 1Password. Use when a site offers 2FA, MFA or an authenticator app during signup or in security settings, when scanning or entering a QR code secret, or when saving backup and recovery codes. Stores the seed so future logins can generate codes; pair with 1pass-read to get a live code and 1pass-create to make the account.
compatibility: Requires curl and jq, and a 1Password Connect server reachable through OP_CONNECT_HOST and OP_CONNECT_TOKEN with write access to the agent's vault.
metadata:
  author: pushkar-anand
  version: "1.0"
---

# Enable two-factor on a website account

Turn 2FA on wherever the site offers it. An agent-held account with a password
alone is one credential leak away from takeover, and 1Password stores the second
factor as readily as the first — so there is no ongoing cost to enabling it.

The account itself comes from `1pass-create`; reading codes back at later logins
is `1pass-read`.

## Do it in one pass

The seed and the recovery codes appear on the same screen, and most sites show
each exactly once. Leaving that screen without both stored is how an account
becomes unrecoverable. Work in this order:

1. Enable 2FA in the site's security settings.
2. Store the seed — `set-totp.sh` prints a live code back.
3. Enter that code to confirm, which is what actually arms 2FA.
4. Store the recovery codes the site then shows.

## Storing the seed

Take whichever form the site offers. The `otpauth://` URI behind the QR code is
better than the bare secret — it carries the issuer and account name. Pass it on
stdin with `-`, which keeps it out of `/proc` and shell history:

```bash
scripts/set-totp.sh github.com - <<'SEED'
otpauth://totp/GitHub:me@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub
SEED
```

If only the "can't scan the code?" text secret is shown, that works too. Spaces
and case do not matter, and the URI is reconstructed from the item:

```bash
scripts/set-totp.sh github.com - <<<'jbsw y3dp ehpk 3pxp'
```

Passing the seed as a plain argument also works and is fine for a throwaway test,
but stdin is the habit worth keeping.

Either way the script stores the seed, re-reads the item, and prints the current
code:

```
Stored a 2FA seed on 'github.com'.
Current code: 452981
```

That read-back is the point. It proves the seed round-tripped and that 1Password
can derive a code from it. **If it errors instead, do not finish enabling 2FA on
the site** — a stored-but-unusable seed locks the account on the next login.
Re-check the secret against what the site displayed.

## Confirming, then recovery codes

Enter the printed code on the site. If it is rejected, fetch a fresh one —
codes last 30 seconds and the first may have expired while typing:

```bash
scripts/set-totp.sh github.com '<same seed>'   # re-stores and reprints
```

Persistent rejection after a fresh code means the seed is wrong, not the clock:
1Password computes codes server-side.

Then capture the recovery codes, which are the only way back in if the seed is
ever lost:

```bash
scripts/set-recovery.sh github.com <<'CODES'
a1b2-c3d4
e5f6-g7h8
CODES
```

They can also be passed as arguments, but stdin keeps them out of `/proc` and
shell history, and handles the multi-line block sites usually display.

## Replacing a seed

Re-running `set-totp.sh` on an item that already has one replaces it and says so.
That is the right move when a site re-issues 2FA, and the wrong move if the old
seed is still live — replace the stored seed only once the site has actually
switched over, or the account is unreachable in between.

## Never put a seed in the transcript

A TOTP seed is a permanent credential — anyone holding it generates valid codes
forever. It is worse to leak than a password, because nothing about the account
visibly changes when it happens.

Pass seeds and recovery codes on **stdin**, never as arguments: arguments are
readable from `/proc` for the life of the process and land in shell history.

```bash
scripts/set-totp.sh github.com -            # seed on stdin
scripts/set-recovery.sh github.com          # codes on stdin
```

**Never** echo a seed or a recovery code back after storing it — not in a
summary, a status message, or a reply to the user. Say "stored the 2FA seed and
recovery codes", never the values. If the seed came from a QR code the agent
read, it is already in context; do not restate it beyond the one command that
stores it.

The 6-digit codes are the mild case — single-use and dead in 30 seconds — so
printing one to confirm 2FA on the site is fine.
