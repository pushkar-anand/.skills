#!/usr/bin/env bash
# Check that this agent can actually write to its vault, before a signup flow
# discovers it cannot halfway through — with the site's TOTP seed on screen and
# nowhere to put it.
#
# Connect tokens carry per-vault read/write scopes chosen when the token is
# issued, and a read-only token fails only at the POST. So this creates a probe
# item and deletes it again rather than inferring permission from a GET.
#
# Usage: preflight.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

probe_id=""
cleanup() {
  [[ -n $probe_id ]] || return 0
  if connect DELETE "/v1/vaults/${vault}/items/${probe_id}" >/dev/null 2>&1; then
    echo "  cleaned up probe item"
  else
    echo "  WARNING: could not delete probe item ${probe_id} — remove it by hand" >&2
  fi
}
trap cleanup EXIT

echo "Connect host: ${OP_CONNECT_HOST}"

vault=$(resolve_vault)
vault_name=$(connect GET /v1/vaults | jq -r --arg v "$vault" '.[] | select(.id == $v) | .name')
echo "Vault:        ${vault_name} (${vault})"

item_count=$(connect GET "/v1/vaults/${vault}/items" | jq 'length')
echo "Read:         OK — ${item_count} items visible"

# The probe carries no secret, so a failed cleanup leaks nothing.
probe_body=$(jq -n --arg v "$vault" '{
  vault: { id: $v },
  title: "preflight-probe (safe to delete)",
  category: "SECURE_NOTE",
  fields: [ { type: "STRING", label: "note", value: "written by onepassword-web-accounts preflight" } ]
}')

if probe_id=$(connect POST "/v1/vaults/${vault}/items" "$probe_body" 2>/dev/null | jq -r '.id // empty'); then
  [[ -n $probe_id ]] || die "write probe returned no item id — Connect response was not an item"
  echo "Write:        OK — token can create items in this vault"
else
  probe_id=""
  die "Write: DENIED.

This token is read-only for '${vault_name}'. Signup flows cannot store anything.
Issue a new Connect token with write access to that vault in 1Password
(Developer > Connect > your server > token), then replace OP_CONNECT_TOKEN
wherever this agent reads its environment from."
fi

# Not required — the scripts here use REST throughout — but worth knowing. If the
# CLI can write through Connect on your setup, ad-hoc edits get much nicer syntax.
# --dry-run makes this non-destructive.
if command -v op >/dev/null 2>&1; then
  if op item create --dry-run --category login --title preflight-probe \
       --vault "$vault" >/dev/null 2>&1; then
    echo "op CLI:       writes appear supported through Connect (bonus, unused here)"
  else
    echo "op CLI:       writes not supported through Connect (expected — REST is used)"
  fi
fi

echo
echo "Ready. See SKILL.md for the signup and login flows."
