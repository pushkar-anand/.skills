#!/usr/bin/env bash
# A skill family sharing scripts/lib.sh (see e.g. the split-skill note in
# README.md) each carries its own copy so that any one installs standalone.
# That duplication is deliberate, but it only stays safe while the copies are
# identical — a fix applied to one and not the others is the failure mode this
# guards against.
#
# Usage: tools/check-lib-sync.sh [--fix]
#   --fix copies the first (alphabetically) copy over the others.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t libs < <(find skills -name lib.sh -type f | sort)
[[ ${#libs[@]} -gt 0 ]] || { echo "no lib.sh copies found"; exit 0; }

canonical=${libs[0]}
copies=("${libs[@]:1}")
[[ ${#copies[@]} -gt 0 ]] || { echo "only one copy (${canonical}) — nothing to compare"; exit 0; }

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
