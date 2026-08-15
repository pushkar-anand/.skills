#!/usr/bin/env bash
# Shared helpers for the 1pass-* skills. Sourced by its siblings; running this
# file directly does nothing.
#
# This copy is byte-identical across 1pass-read, 1pass-create and 1pass-2fa so
# each skill installs standalone. tools/check-lib-sync.sh enforces that.
#
# Everything here talks to the Connect REST API rather than the `op` CLI. The CLI's
# Connect mode is documented to cover `op read`, `op inject`, `op run` and
# `op item get` only — item create/edit are not on that list — so a script that
# writes has to speak HTTP. Reads go the same way for one auth path, one error
# model, and because a GET already carries the live TOTP code (see totp_of).

set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# No apostrophes in these messages: the word in ${var:?word} is parsed for
# quoting, so a lone ' opens a quote that swallows the rest of the file.
: "${OP_CONNECT_HOST:?not set — point it at your 1Password Connect server}"
: "${OP_CONNECT_TOKEN:?not set — a Connect token scoped to the vault for this agent}"

command -v curl >/dev/null || die "curl is required"
command -v jq   >/dev/null || die "jq is required"

# connect <method> <path> [json-body]
#
# The body goes over stdin, never argv: request bodies carry passwords and TOTP
# seeds, and argv is world-readable in /proc. The bearer token stays a header
# argument — it is already in the environment of this process, so hiding it from
# argv would buy nothing.
connect() {
  local method=$1 path=$2 body=${3-}
  local -a args=(
    --silent --show-error --fail-with-body
    --header "Authorization: Bearer ${OP_CONNECT_TOKEN}"
    --header "Content-Type: application/json"
    --request "$method"
  )
  if [[ -n $body ]]; then
    curl "${args[@]}" --data @- "${OP_CONNECT_HOST%/}${path}" <<<"$body"
  else
    curl "${args[@]}" "${OP_CONNECT_HOST%/}${path}"
  fi
}

# resolve_vault -> vault UUID
#
# A Connect token is normally scoped to a single vault for one agent, so "the
# vault" is the only one it can see and needs no argument. OP_VAULT (name or UUID)
# settles it when a token reaches more than one.
resolve_vault() {
  local vaults id
  # One message for both failures on purpose: curl reports a refused connection
  # and a rejected token the same way, and guessing between them sends whoever
  # reads this to debug the wrong one.
  vaults=$(connect GET /v1/vaults) \
    || die "Connect request failed at ${OP_CONNECT_HOST} — check the server is up, OP_CONNECT_HOST is right, and OP_CONNECT_TOKEN is valid (a 401 above means the token)"

  if [[ -n ${OP_VAULT-} ]]; then
    id=$(jq -r --arg v "$OP_VAULT" \
      'map(select(.id == $v or .name == $v)) | .[0].id // empty' <<<"$vaults")
    [[ -n $id ]] || die "OP_VAULT=${OP_VAULT} matches no vault this token can reach"
    printf '%s' "$id"
    return
  fi

  local n; n=$(jq 'length' <<<"$vaults")
  case $n in
    0) die "this token reaches no vaults — has the Connect server been granted the agent vault?" ;;
    1) jq -r '.[0].id' <<<"$vaults" ;;
    *) die "this token reaches ${n} vaults; set OP_VAULT to choose one" ;;
  esac
}

# find_items <vault> <query> -> JSON array of item summaries (no field values)
#
# Filtering client-side rather than with the API filter= parameter: an agent vault
# holds tens of items, and this matches a substring of the title or of any saved
# URL instead of only an exact title.
find_items() {
  local vault=$1 query=$2
  connect GET "/v1/vaults/${vault}/items" | jq --arg q "${query,,}" '
    [ .[] | select(
        ((.title // "") | ascii_downcase | contains($q))
        or (((.urls // []) | map(.href // "") | join(" ") | ascii_downcase) | contains($q))
      ) ]'
}

# resolve_item <vault> <query> -> item UUID
#
# A 26-32 character alphanumeric query is taken as a UUID and used as-is. Anything
# else is a search, and an ambiguous search is an error rather than a guess —
# picking the wrong login is worse than stopping.
resolve_item() {
  local vault=$1 query=$2

  if [[ $query =~ ^[a-z0-9]{26,32}$ ]]; then
    printf '%s' "$query"
    return
  fi

  local matches n listing
  matches=$(find_items "$vault" "$query")
  n=$(jq 'length' <<<"$matches")

  case $n in
    0) die "no item matches ${query} in this vault" ;;
    1) jq -r '.[0].id' <<<"$matches" ;;
    *) listing=$(jq -r '.[] | "  \(.id)  \(.title)"' <<<"$matches")
       die "${query} matches ${n} items:
${listing}
Re-run with the exact title or the item ID." ;;
  esac
}

# get_item <vault> <item-uuid> -> full item JSON, field values included
#
# The collection endpoint returns summaries with no values, so reading a secret
# always costs this second call.
get_item() {
  connect GET "/v1/vaults/${1}/items/${2}"
}

# field_of <purpose-or-label> <item-json>  — USERNAME / PASSWORD by purpose,
# anything else by case-insensitive label match.
field_of() {
  jq -r --arg k "${1,,}" '
    ( .fields // [] )
    | map(select((.purpose // "" | ascii_downcase) == $k
              or (.label   // "" | ascii_downcase) == $k))
    | .[0].value // empty' <<<"$2"
}

# totp_of <item-json> — the current 6-digit code.
#
# Connect computes this server-side and returns it in the OTP field totp property
# alongside the otpauth:// seed in value, so no local TOTP implementation and no
# clock of our own is involved.
totp_of() {
  jq -r '( .fields // [] )
    | map(select(.type == "OTP"))
    | .[0].totp // empty' <<<"$1"
}
