#!/usr/bin/env bash
# Frontmatter smoke test for the stride-copilot-exploratory-testing plugin.
#
# Asserts every skill and agent carries the YAML frontmatter keys Copilot
# needs to load it:
#   - skills/*/SKILL.md    : name, description
#   - agents/*.agent.md    : name, description, tools   (description may be a
#                            `description: |` block scalar)
# Pure shell — no network, no jq. Copilot agents use the .agent.md extension,
# and there is no commands/ directory to check.
#
# Exit code: 0 if every check passes; 1 if any check fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$(( PASS + 1 )); printf '  ✓  %s\n' "$1"; }
nope() { FAIL=$(( FAIL + 1 )); printf '  ✗  %s\n     %s\n' "$1" "${2:-}"; }

# Print the YAML frontmatter block (the lines between the first two `---`
# fences). Requires the file to open with `---` on line 1.
extract_frontmatter() {
  awk '
    /^---[[:space:]]*$/ { c++; if (c >= 2) exit; next }
    c == 1 { print }
  ' "$1"
}

# True when the frontmatter block declares KEY (matches `key:` at the start
# of a line — works for inline values and `key: |` block scalars alike).
has_key() {
  extract_frontmatter "$1" | grep -qE "^$2:"
}

# Check that FILE (relative label $1, path $2) declares every key in $3..$n.
check_keys() {
  local label="$1" file="$2"; shift 2
  if [ ! -f "$file" ]; then
    nope "${label} is missing" "$file"
    return
  fi
  local missing=""
  local key
  for key in "$@"; do
    if ! has_key "$file" "$key"; then
      missing="${missing} ${key}"
    fi
  done
  if [ -z "$missing" ]; then
    ok "${label} declares:$(printf ' %s' "$@")"
  else
    nope "${label} is missing frontmatter key(s):${missing}" ""
  fi
}

printf 'stride-copilot-exploratory-testing frontmatter smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- Skills: name + description --------------------------------------------

printf 'Skills (name, description)\n'
for skill_md in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
  [ -e "$skill_md" ] || { nope "no SKILL.md files found under skills/" ""; break; }
  rel="skills/$(basename "$(dirname "$skill_md")")/SKILL.md"
  check_keys "$rel" "$skill_md" name description
done

# --- Agents: name + description + tools ------------------------------------

printf '\nAgents (name, description, tools)\n'
for agent_md in "${PLUGIN_ROOT}"/agents/*.agent.md; do
  [ -e "$agent_md" ] || { nope "no *.agent.md files found under agents/" ""; break; }
  rel="agents/$(basename "$agent_md")"
  check_keys "$rel" "$agent_md" name description tools
done

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
