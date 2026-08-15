#!/usr/bin/env bash
# Print the vault this agent is working in.
#
# The other scripts never need this — they resolve the vault themselves. It
# exists because an op:// secret reference has to name the vault literally, and
# this is the cheapest way to find out what to put there:
#
#   op read "op://$(vault.sh)/github.com/password"
#
# Usage: vault.sh [--id]
#   --id   print the UUID instead of the name

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Both branches go through a command substitution so the trailing newline is
# normalised: resolve_vault emits one on the auto-detect path and not on the
# OP_VAULT path, and $(...) strips either.
case ${1-} in
  --id) printf '%s\n' "$(resolve_vault)" ;;
  "")   id=$(resolve_vault)
        printf '%s\n' "$(connect GET /v1/vaults | jq -r --arg v "$id" '.[] | select(.id == $v) | .name')" ;;
  *)    die "usage: vault.sh [--id]" ;;
esac
