#!/usr/bin/env bash
# Run a command with stored credentials in its environment, without any of them
# passing through the transcript.
#
# This and `op read` solve the same problem; pick whichever fits the moment.
#
#   op read   is fewer moving parts and needs no script. Best when the item title
#             and vault name are already known and one secret is needed:
#               PASSWORD=$(op read "op://<vault>/github.com/password")
#
#   run.sh    resolves the item by domain instead of needing its exact title,
#             needs no vault name, pulls several fields in one call, and takes
#             VAR=totp for a live code without the ?attribute=otp syntax.
#
# Usage: run.sh <item> VAR=field [VAR=field ...] -- <command> [args...]
#
# Examples:
#   run.sh github.com GH_USER=username GH_TOKEN=password -- ./deploy.sh
#   run.sh github.com CODE=totp -- ./login.sh
#
# <field> is username, password, totp, or any custom label ("recovery codes").
#
# For a config file rather than an environment, combine this with a renderer:
#   run.sh site.com PASSWORD=password -- sh -c 'envsubst < config.tmpl > config'
# or use `op inject` when a template needs several secrets substituted at once.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "usage: run.sh <item> VAR=field [VAR=field ...] -- <command> [args...]"
query=$1; shift

mappings=()
while [[ $# -gt 0 && $1 != "--" ]]; do
  [[ $1 == *=* ]] || die "expected VAR=field or -- before the command, got: $1"
  mappings+=("$1")
  shift
done

[[ ${1-} == "--" ]] || die "missing -- before the command"
shift
[[ $# -gt 0 ]] || die "no command after --"
[[ ${#mappings[@]} -gt 0 ]] || die "no VAR=field mappings given"

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$query")
item=$(get_item "$vault" "$item_id")

# Built as an array so values containing spaces, newlines or shell metacharacters
# reach the child intact and never get re-parsed by a shell.
assignments=()
for pair in "${mappings[@]}"; do
  var=${pair%%=*}
  field=${pair#*=}
  [[ $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "not a valid variable name: ${var}"

  if [[ $field == "totp" ]]; then
    value=$(totp_of "$item")
    [[ -n $value ]] || die "no 2FA stored on '$(jq -r '.title' <<<"$item")'"
  else
    value=$(field_of "$field" "$item")
    [[ -n $value ]] || die "no field '${field}' on '$(jq -r '.title' <<<"$item")'"
  fi

  assignments+=("${var}=${value}")
done

exec env "${assignments[@]}" "$@"
