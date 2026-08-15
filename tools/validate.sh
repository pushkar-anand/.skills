#!/usr/bin/env bash
# Validate every skill in this repo against the Agent Skills spec, and check the
# repo-local invariants the spec does not cover.
#
# Usage: tools/validate.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fails=0
note() { printf '  %s\n' "$*"; fails=$((fails + 1)); }

while IFS= read -r skill; do
  dir=$(dirname "$skill")
  expected=$(basename "$dir")
  echo "${dir#./}"

  # Frontmatter is the block between the first two --- lines.
  fm=$(awk 'NR==1 && $0 != "---" { exit } NR>1 && $0 == "---" { exit } NR>1' "$skill")
  [[ -n $fm ]] || { note "no YAML frontmatter"; continue; }

  name=$(sed -n 's/^name:[[:space:]]*//p' <<<"$fm" | head -1)
  desc=$(sed -n 's/^description:[[:space:]]*//p' <<<"$fm" | head -1)

  [[ -n $name ]] || note "missing required field: name"
  [[ -n $desc ]] || note "missing required field: description"

  # The spec pins name to the directory name; getting this wrong makes the skill
  # unloadable in some clients and silently misnamed in others.
  [[ $name == "$expected" ]] || note "name '${name}' does not match directory '${expected}'"

  [[ $name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
    || note "name '${name}' must be lowercase alphanumeric with single hyphens, no leading/trailing hyphen"
  [[ ${#name} -le 64 ]] || note "name is ${#name} chars, max 64"
  [[ ${#desc} -le 1024 ]] || note "description is ${#desc} chars, max 1024"

  # Not a spec rule, but a description this short cannot carry both what the skill
  # does and when to use it — which is all the model sees before it fires.
  [[ ${#desc} -ge 40 ]] || note "description is only ${#desc} chars; say what it does AND when to use it"

  lines=$(wc -l < "$skill")
  [[ $lines -le 500 ]] || note "SKILL.md is ${lines} lines; move detail into references/"

  while IFS= read -r script; do
    [[ -x $script ]] || note "not executable: ${script#"$dir"/}"
    bash -n "$script" 2>/dev/null || note "bash syntax error: ${script#"$dir"/}"
  done < <(find "$dir" -name '*.sh' -type f)
done < <(find skills -name SKILL.md -type f | sort)

echo
if [[ $fails -eq 0 ]]; then
  echo "OK — all skills valid."
else
  echo "${fails} problem(s) found."
  exit 1
fi
