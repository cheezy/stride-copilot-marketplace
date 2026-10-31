#!/usr/bin/env bash
# Top-level offline test runner for the stride-copilot-security-review plugin.
#
# Runs every offline check in sequence and exits non-zero if any fails: the
# fixture/EXPECTED.md parity guard (check_fixtures.sh), the agent contract
# check (check_agent_contract.sh) and the eval invocation check
# (check_eval_invocation.sh), in the order .github/workflows/eval.yml runs
# them, then the git hardening check (check_git_hardening.sh, which runs the
# pinned git forms against a scratch repository and is not yet a CI step);
# later port tasks add theirs here. Offline and read-only: it needs only
# bash, jq, python3 (the agent contract counts the body in code points) and
# standard Unix tools, with no Copilot CLI and no token, and its
# self-tests write only to a temporary directory, removed on exit. Suitable for
# gating a release.
#
# The agent eval runner (run_eval.sh) is a separate entry point: it dispatches
# the agent through a live Copilot CLI. See its header.
#
# Usage:
#   bash scripts/test-all.sh
#
# Exit code: 0 only if ALL checks pass; 1 if any fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

FAILED=0

printf '=== fixture parity ===\n'
if bash "${SCRIPT_DIR}/check_fixtures.sh"; then
  :
else
  FAILED=1
fi

printf '\n=== agent contract ===\n'
if bash "${SCRIPT_DIR}/check_agent_contract.sh"; then
  :
else
  FAILED=1
fi

printf '\n=== eval invocation ===\n'
if bash "${SCRIPT_DIR}/check_eval_invocation.sh"; then
  :
else
  FAILED=1
fi

printf '\n=== git hardening ===\n'
if bash "${SCRIPT_DIR}/check_git_hardening.sh" </dev/null; then
  :
else
  FAILED=1
fi

# The runner's own break-it: a copy of the tree with a broken tools line must
# make this runner fail, and an unbroken copy must make it pass. TEST_ALL_CHILD
# stops the copies running this self-test again, and CHECK_AGENT_CONTRACT_CHILD
# skips the contract check's self-tests there (they already ran above).
if [ -z "${TEST_ALL_CHILD:-}" ]; then
  printf '\n=== runner self-test ===\n'
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-all.XXXXXX")" || {
    printf 'FAIL: self-test: could not create a temporary directory\n'; exit 1; }
  trap 'rm -rf "$TMP"' EXIT

  mkdir "$TMP/good"
  cp -R "$ROOT/agents" "$ROOT/skills" "$ROOT/docs" "$ROOT/scripts" "$ROOT/test" "$ROOT/.github" \
    "$ROOT/plugin.json" "$ROOT/README.md" "$TMP/good/"
  cp -R "$TMP/good" "$TMP/broken"
  cp -R "$TMP/good" "$TMP/no-row"
  cp -R "$TMP/good" "$TMP/no-agent"
  A="$TMP/broken/agents/security-reviewer.agent.md"
  awk '/^tools:/ && !d { sub(/\]$/, ", \"edit\"]"); d = 1 } { print }' "$A" > "$A.new" && mv "$A.new" "$A"
  E="$TMP/no-row/test/fixtures/EXPECTED.md"
  grep -v 'considerations/search_sort_partial.diff' "$E" > "$E.new" && mv "$E.new" "$E"
  R="$TMP/no-agent/scripts/run_eval.sh"
  grep -vxF '    --agent "$AGENT"' "$R" > "$R.new" && mv "$R.new" "$R"

  # run_copy <tree> -> sets out and rc
  run_copy() {
    out="$(TEST_ALL_CHILD=1 CHECK_AGENT_CONTRACT_CHILD=1 bash "$1/scripts/test-all.sh" 2>&1)"; rc=$?
  }

  run_copy "$TMP/good"
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF 'ALL CHECKS PASSED'; then
    printf 'ok: self-test: an unbroken copy passes the runner\n'
  else
    printf 'FAIL: self-test: an unbroken copy passes the runner -- exit %s\n' "$rc"; FAILED=1
  fi

  run_copy "$TMP/broken"
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'ONE OR MORE CHECKS FAILED' \
      && printf '%s\n' "$out" | grep -qF 'FAIL: the frontmatter tools line'; then
    printf 'ok: self-test: a failing contract check makes the runner exit non-zero\n'
  else
    printf 'FAIL: self-test: a failing contract check makes the runner exit non-zero -- exit %s\n' "$rc"; FAILED=1
  fi

  run_copy "$TMP/no-row"
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'ONE OR MORE CHECKS FAILED' \
      && printf '%s\n' "$out" | grep -qF 'Fixture files with no EXPECTED.md row'; then
    printf 'ok: self-test: a failing fixture parity check makes the runner exit non-zero\n'
  else
    printf 'FAIL: self-test: a failing fixture parity check makes the runner exit non-zero -- exit %s\n' "$rc"; FAILED=1
  fi

  run_copy "$TMP/no-agent"
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'ONE OR MORE CHECKS FAILED' \
      && printf '%s\n' "$out" | grep -qF 'FAIL: the invocation selects the plugin agent'; then
    printf 'ok: self-test: a failing eval invocation check makes the runner exit non-zero\n'
  else
    printf 'FAIL: self-test: a failing eval invocation check makes the runner exit non-zero -- exit %s\n' "$rc"; FAILED=1
  fi
fi

printf '\n=== result ===\n'
if [ "$FAILED" -eq 0 ]; then
  printf 'ALL CHECKS PASSED\n'
  exit 0
else
  printf 'ONE OR MORE CHECKS FAILED\n'
  exit 1
fi
