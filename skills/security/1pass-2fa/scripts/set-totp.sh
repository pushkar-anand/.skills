#!/usr/bin/env bash
# Store a site's 2FA seed on its login item, then print the current code so the
# same run can finish the site's "enter a code to confirm" step.
#
# Store the seed the moment the site shows it. Most sites reveal it exactly once,
# and an account whose seed was never captured is one the agent locks itself out
# of at the next login.
#
# Accepts either form the site offers:
#   an otpauth:// URI   (what the QR code encodes — prefer this, it carries issuer)
#   a bare base32 secret (the "can't scan the code?" text, spaces are fine)
#
# Usage: set-totp.sh <item> <otpauth-uri-or-secret>
#        set-totp.sh <item> -            # read the seed from stdin
#
# Connect has no PATCH — the official SDK only ever PUTs a whole item — so this
# is a read-modify-write. The item is fetched, the OTP field replaced or appended,
# and the full object sent back.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 2 ]] || die "usage: set-totp.sh <item> <otpauth-uri-or-secret|->"

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$1")
seed=$2
[[ $seed == "-" ]] && seed=$(cat)
[[ -n $seed ]] || die "no seed given"

item=$(get_item "$vault" "$item_id")
title=$(jq -r '.title' <<<"$item")

if [[ $seed == otpauth://* ]]; then
  uri=$seed
else
  # Base32, case-insensitive, commonly shown in space-separated groups.
  secret=${seed//[[:space:]]/}
  secret=${secret^^}
  [[ $secret =~ ^[A-Z2-7]+=*$ ]] \
    || die "'${seed}' is neither an otpauth:// URI nor a base32 secret"

  account=$(field_of USERNAME "$item")
  : "${account:=$title}"
  uri=$(jq -rn --arg s "$secret" --arg i "$title" --arg a "$account" \
    '"otpauth://totp/\($i|@uri):\($a|@uri)?secret=\($s)&issuer=\($i|@uri)"')
fi

had_otp=$(jq -r '(.fields // []) | map(select(.type == "OTP")) | length' <<<"$item")

updated=$(jq --arg uri "$uri" '
  .fields = (
    if ((.fields // []) | any(.type == "OTP"))
    then (.fields | map(if .type == "OTP" then .value = $uri else . end))
    else ((.fields // []) + [{ type: "OTP", label: "one-time password", value: $uri }])
    end)' <<<"$item")

connect PUT "/v1/vaults/${vault}/items/${item_id}" "$updated" >/dev/null \
  || die "update failed — run 1pass-create's preflight.sh to check this token can write"

# Re-read rather than trusting the PUT echo: this proves the seed round-tripped
# and that Connect can derive a code from it. A seed that stores but yields no
# code is a locked-out account, and better discovered now than at next login.
code=$(totp_of "$(get_item "$vault" "$item_id")")
[[ -n $code ]] || die "seed stored on ${item_id} but Connect returned no code — the seed is probably malformed; re-check it against the site before leaving 2FA enabled"

if [[ $had_otp -gt 0 ]]; then
  echo "Replaced the existing 2FA seed on '${title}'."
else
  echo "Stored a 2FA seed on '${title}'."
fi
echo "Current code: ${code}"
echo
echo "Enter it on the site to confirm 2FA, then save the recovery codes:"
echo "  set-recovery.sh ${item_id}      # codes on stdin, one per line"
