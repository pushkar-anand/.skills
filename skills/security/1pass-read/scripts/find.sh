#!/usr/bin/env bash
# Discover stored accounts. Prints no secrets — id, title, username, URLs and
# whether 2FA is stored — so it is always safe to run and safe to leave in a log.
#
# With a query it answers "do I have an account here?", which is the lookup an
# `op://Vault/Item/field` reference cannot do: that needs the item name, and
# during a login the agent has a URL instead.
#
# With no query it lists every account in the vault, which is how the agent finds
# out what it already has before deciding to sign up for anything.
#
# Usage: find.sh [domain-or-text]
#        find.sh github.com
#        find.sh                  # everything in the vault

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -le 1 ]] || die "usage: find.sh [domain-or-text]"
query=${1-}

vault=$(resolve_vault)

if [[ -n $query ]]; then
  matches=$(find_items "$vault" "$query")
else
  matches=$(connect GET "/v1/vaults/${vault}/items")
fi

count=$(jq 'length' <<<"$matches")

if [[ $count -eq 0 ]]; then
  if [[ -n $query ]]; then
    echo "No account stored for '${query}'."
    echo "If signing up, 1pass-create's create.sh makes one."
  else
    echo "No accounts stored in this vault yet."
  fi
  exit 0
fi

# The vault name is printed because it is the first component of an op:// secret
# reference, and `op read` is the preferred way to consume any of these values.
vault_name=$(connect GET /v1/vaults | jq -r --arg v "$vault" '.[] | select(.id == $v) | .name')
if [[ -n $query ]]; then
  echo "vault: ${vault_name}"
else
  echo "vault: ${vault_name} — ${count} accounts"
fi
echo

# The collection endpoint omits field values, so username and 2FA status cost one
# GET each. Agent vaults are small, and this stays well inside a normal listing.
jq -r '.[].id' <<<"$matches" | while read -r id; do
  item=$(get_item "$vault" "$id")
  printf '%s\n' "$(jq -r '.title' <<<"$item")"
  printf '  id:       %s\n' "$id"
  printf '  username: %s\n' "$(field_of USERNAME "$item")"
  printf '  urls:     %s\n' "$(jq -r '[(.urls // [])[].href] | join(", ")' <<<"$item")"
  printf '  ref:      op://%s/%s/<field>\n' "$vault_name" "$(jq -r '.title' <<<"$item")"
  # Presence is "an OTP field carrying a seed" — not "a field with an id". Field
  # ids are assigned by the server and absent on anything written this session.
  if [[ $(jq -r '(.fields // []) | any(.type == "OTP" and (.value // "") != "")' <<<"$item") == true ]]; then
    printf '  2fa:      stored (totp.sh %s for a live code)\n' "$id"
  else
    printf '  2fa:      none stored\n'
  fi
  printf '\n'
done
