#!/usr/bin/env bash
# Add or replace a labelled field on a stored account.
#
# Exists mainly for the things a signup hands over once and never shows again:
# recovery codes, backup codes, security-question answers, an account number.
# Recovery codes matter as much as the 2FA seed — they are the way back in when
# the seed is lost, and the site shows them exactly once.
#
# Usage: set-field.sh <item> <label> <type> <value|->
#   <type> is concealed | string | url | email
#   a value of - reads from stdin, which is how multi-line recovery codes go in
#
# Examples:
#   set-field.sh github.com 'recovery codes' concealed -
#   set-field.sh github.com 'signup email' email me@example.com
#
# Rotating a password is the same operation:
#   set-field.sh github.com password concealed -

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 4 ]] || die "usage: set-field.sh <item> <label> <concealed|string|url|email> <value|->"

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$1")
label=$2
value=$4
[[ $value == "-" ]] && value=$(cat)
[[ -n $value ]] || die "no value given"

case ${3,,} in
  concealed) type=CONCEALED ;;
  string)    type=STRING ;;
  url)       type=URL ;;
  email)     type=EMAIL ;;
  *)         die "type must be one of: concealed, string, url, email" ;;
esac

item=$(get_item "$vault" "$item_id")
title=$(jq -r '.title' <<<"$item")

# Matched on purpose first so `set-field.sh <item> password ...` rotates the real
# password field rather than appending a second one beside it.
updated=$(jq --arg label "$label" --arg value "$value" --arg type "$type" '
  ($label | ascii_downcase) as $key
  | ((.fields // []) | map(
      ((.purpose // "" | ascii_downcase) == $key) or
      ((.label   // "" | ascii_downcase) == $key)) | index(true)) as $at
  | .fields = (
      if $at == null
      then ((.fields // []) + [{ type: $type, label: $label, value: $value }])
      else (.fields | .[$at].value = $value | .[$at].generate = false)
      end)' <<<"$item")

connect PUT "/v1/vaults/${vault}/items/${item_id}" "$updated" >/dev/null \
  || die "update failed — run preflight.sh to check this token can write"

existed=$(jq -r --arg k "${label,,}" '
  (.fields // []) | any((.purpose // "" | ascii_downcase) == $k
                     or (.label   // "" | ascii_downcase) == $k)' <<<"$item")

if [[ $existed == true ]]; then
  echo "Replaced '${label}' on '${title}'."
else
  echo "Added '${label}' to '${title}'."
fi
