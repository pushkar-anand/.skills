#!/usr/bin/env bash
# Store the recovery codes a site hands out when 2FA is switched on.
#
# These matter as much as the seed itself: they are the only way back in if the
# seed is lost, and the site shows them exactly once, on the same screen as the
# QR code. Capture them in the same run that stores the seed.
#
# Usage: set-recovery.sh <item> [codes...]
#        set-recovery.sh <item>            # reads them from stdin, one per line
#
# Stored as a single concealed field so `1pass-read`'s show.sh prints them back
# verbatim, newlines and all.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "usage: set-recovery.sh <item> [codes...]"

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$1"); shift

if [[ $# -gt 0 ]]; then
  codes=$(printf '%s\n' "$@")
else
  codes=$(cat)
fi
[[ -n ${codes//[[:space:]]/} ]] || die "no recovery codes given"

count=$(grep -c '[^[:space:]]' <<<"$codes" || true)

item=$(get_item "$vault" "$item_id")
title=$(jq -r '.title' <<<"$item")

if [[ $(jq -r '(.fields // []) | any(.type == "OTP" and (.value // "") != "")' <<<"$item") != true ]]; then
  echo "note: '${title}' has no 2FA seed stored yet — set-totp.sh stores that." >&2
fi

updated=$(jq --arg codes "$codes" '
  ((.fields // []) | map((.label // "" | ascii_downcase) == "recovery codes") | index(true)) as $at
  | .fields = (
      if $at == null
      then ((.fields // []) + [{ type: "CONCEALED", label: "recovery codes", value: $codes }])
      else (.fields | .[$at].value = $codes)
      end)' <<<"$item")

connect PUT "/v1/vaults/${vault}/items/${item_id}" "$updated" >/dev/null \
  || die "update failed — run 1pass-create's preflight.sh to check this token can write"

echo "Stored ${count} recovery codes on '${title}'."
