#!/usr/bin/env bash
# Read one stored field.
#
# One field per call, named explicitly. Dumping a whole item would put every
# secret on it into the transcript when only one of them was needed.
#
# Usage: show.sh <item> <field> [--exec <command> [args...]]
#   <field> is username, password, or any custom label ("recovery codes")
#
#   --exec  pipe the value into <command> on stdin and print nothing. The secret
#           goes process-to-process and never enters the transcript, the model
#           context, or the gateway logs. Prefer this wherever the consumer is a
#           command rather than the model itself.
#
# Examples:
#   show.sh github.com password --exec browser-fill '#password'
#   show.sh github.com password            # prints — see the warning it emits
#
# Without --exec the value goes to stdout, which means the transcript and the
# logs. That is unavoidable when the model has to type it into a form, and
# pointless otherwise, so this warns on stderr every time it does it.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 2 ]] || die "usage: show.sh <item> <field> [--exec <command> [args...]]"
query=$1 field=$2; shift 2

exec_cmd=()
if [[ $# -gt 0 ]]; then
  [[ $1 == --exec ]] || die "unknown option: $1"
  shift
  [[ $# -gt 0 ]] || die "--exec needs a command"
  exec_cmd=("$@")
fi

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$query")
item=$(get_item "$vault" "$item_id")

value=$(field_of "$field" "$item")
if [[ -z $value ]]; then
  die "no field '${field}' on '$(jq -r '.title' <<<"$item")'. Fields present:
$(jq -r '(.fields // [])[] | "  \(.label // (.purpose // "" | ascii_downcase))"' <<<"$item" | sort -u)"
fi

if [[ ${#exec_cmd[@]} -gt 0 ]]; then
  printf '%s' "$value" | "${exec_cmd[@]}"
  exit
fi

# Only the username is safe to print without comment; everything else on a login
# item is a credential.
case ${field,,} in
  username|email) ;;
  *) printf 'warning: %s for %s is now in the transcript and the logs. Use it, then do not repeat it. --exec avoids this.\n' \
       "$field" "$(jq -r '.title' <<<"$item")" >&2 ;;
esac

printf '%s\n' "$value"
