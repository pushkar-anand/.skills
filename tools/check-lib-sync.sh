#!/usr/bin/env bash
# The 1pass-* skills each carry their own copy of scripts/lib.sh so that any one
# of them installs standalone. That duplication is deliberate, but it only stays
# safe while the copies are identical — a fix applied to one and not the others is
# the failure mode this guards against.
#
# Usage: tools/check-lib-sync.sh [--fix]
#   --fix copies the 1pass-read copy over the others.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

canonical=skills/security/1pass-read/scripts/lib.sh
[[ -f $canonical ]] || { echo "missing canonical lib: ${canonical}" >&2; exit 1; }

mapfile -t copies < <(find skills -name lib.sh -type f | grep -v "^${canonical}$" | sort)
[[ ${#copies[@]} -gt 0 ]] || { echo "no other copies found"; exit 0; }

drift=0
for copy in "${copies[@]}"; do
  if cmp -s "$canonical" "$copy"; then
    echo "ok    ${copy}"
  elif [[ ${1-} == --fix ]]; then
    cp "$canonical" "$copy"
    echo "fixed ${copy}"
  else
    echo "DRIFT ${copy}"
    diff -u "$canonical" "$copy" | sed 's/^/      /' || true
    drift=$((drift + 1))
  fi
done

if [[ $drift -gt 0 ]]; then
  echo
  echo "${drift} copy(s) differ from ${canonical}. Re-run with --fix to sync."
  exit 1
fi
