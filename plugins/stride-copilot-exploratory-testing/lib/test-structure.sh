#!/usr/bin/env bash
# Structure smoke test for the stride-copilot-exploratory-testing plugin.
#
# Asserts the plugin ships every file the Copilot plugin schema and this
# plugin's docs require: a valid ROOT manifest, all six core knowledge
# skills, all seven command-derived skills, both .agent.md agents, the three
# README-referenced fixtures, and the root docs. Pure shell + python3 (for
# JSON) — no network, no jq.
#
# Copilot conventions (differ from the Claude Code upstream):
#   - plugin.json lives at the repository ROOT (not under .claude-plugin/)
#   - agents use the .agent.md extension (not .md)
#   - there is NO commands/ directory (the upstream commands are skills)
#
# Exit code: 0 if every check passes; 1 if any check fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

ok()   { PASS=$(( PASS + 1 )); printf '  ✓  %s\n' "$1"; }
nope() { FAIL=$(( FAIL + 1 )); printf '  ✗  %s\n     %s\n' "$1" "${2:-}"; }

printf 'stride-copilot-exploratory-testing structure smoke test\n'
printf 'plugin root: %s\n\n' "$PLUGIN_ROOT"

# --- Manifest (ROOT plugin.json) -------------------------------------------

MANIFEST="${PLUGIN_ROOT}/plugin.json"
if [ -f "$MANIFEST" ]; then
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/tmp/et-manifest.err; then
    ok "plugin.json exists at the root and is valid JSON"
    if python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
missing = [k for k in ('name', 'description', 'version', 'agents', 'skills') if k not in d]
sys.exit(1 if missing else 0)
" "$MANIFEST"; then
      ok "plugin.json has the required keys (name, description, version, agents, skills)"
    else
      nope "plugin.json is missing one of: name, description, version, agents, skills" ""
    fi
  else
    nope "plugin.json is not valid JSON" "$(cat /tmp/et-manifest.err)"
  fi
  rm -f /tmp/et-manifest.err
else
  nope "plugin.json not found at the plugin root" "$MANIFEST"
fi

# --- Core knowledge skills -------------------------------------------------

for skill in stride-exploratory-testing chartering heuristics oracles bug-advocacy session; do
  if [ -f "${PLUGIN_ROOT}/skills/${skill}/SKILL.md" ]; then
    ok "skills/${skill}/SKILL.md exists"
  else
    nope "skills/${skill}/SKILL.md is missing" ""
  fi
done

# --- Command-derived skills (replace the upstream slash commands) -----------

for skill in \
  stride-exploratory-testing-charter \
  stride-exploratory-testing-nightmare-headline \
  stride-exploratory-testing-explore \
  stride-exploratory-testing-recon \
  stride-exploratory-testing-debrief \
  stride-exploratory-testing-pair \
  stride-exploratory-testing-harden; do
  if [ -f "${PLUGIN_ROOT}/skills/${skill}/SKILL.md" ]; then
    ok "skills/${skill}/SKILL.md exists"
  else
    nope "skills/${skill}/SKILL.md is missing" ""
  fi
done

# Count only real SKILL.md files (any .gitkeep placeholder is ignored).
SKILL_COUNT=$(find "${PLUGIN_ROOT}/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -eq 13 ]; then
  ok "exactly 13 SKILL.md files present (6 core + 7 command-derived; .gitkeep ignored)"
else
  nope "expected 13 SKILL.md files, found ${SKILL_COUNT}" ""
fi

# --- Agents (.agent.md extension) ------------------------------------------

for agent in charter-generator explorer; do
  if [ -f "${PLUGIN_ROOT}/agents/${agent}.agent.md" ]; then
    ok "agents/${agent}.agent.md exists"
  else
    nope "agents/${agent}.agent.md is missing" ""
  fi
done

# Count only *.agent.md files (any .gitkeep placeholder is ignored).
AGENT_COUNT=$(find "${PLUGIN_ROOT}/agents" -maxdepth 1 -name '*.agent.md' | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -eq 2 ]; then
  ok "exactly 2 agent files present (.gitkeep ignored)"
else
  nope "expected 2 agent files, found ${AGENT_COUNT}" ""
fi

# --- Fixtures (referenced by README.md) ------------------------------------

for fixture in example-charters.md example-session-sheet.md example-debrief.md; do
  if [ -f "${PLUGIN_ROOT}/fixtures/${fixture}" ]; then
    ok "fixtures/${fixture} exists"
  else
    nope "fixtures/${fixture} is missing" ""
  fi
done

# --- Root docs -------------------------------------------------------------

for doc in README.md CHANGELOG.md LICENSE; do
  if [ -f "${PLUGIN_ROOT}/${doc}" ]; then
    ok "${doc} exists"
  else
    nope "${doc} is missing" ""
  fi
done

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
