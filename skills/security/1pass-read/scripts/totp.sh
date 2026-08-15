#!/usr/bin/env bash
# Print the current 2FA code for a stored account, and nothing else — so it can
# be piped straight into a form fill.
#
# Connect derives the code server-side and returns it in the OTP field's `totp`,
# so there is no TOTP implementation and no clock skew of our own here.
#
# `op item get <item> --otp` may also work, but the CLI's Connect mode is only
# documented for read/inject/run/item-get; this path is guaranteed.
#
# Usage: totp.sh <item>

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -eq 1 ]] || die "usage: totp.sh <item>"

vault=$(resolve_vault)
item_id=$(resolve_item "$vault" "$1")
item=$(get_item "$vault" "$item_id")

code=$(totp_of "$item")
[[ -n $code ]] || die "no 2FA stored on '$(jq -r '.title' <<<"$item")' — add it with set-totp.sh"

printf '%s\n' "$code"
