#!/usr/bin/env bash
# Token-free checks on how scripts/run_eval.sh invokes the agent (W2570,
# porting upstream W2274).
#
# The eval is only worth running if it dispatches THIS plugin's
# security-reviewer agent through Copilot CLI rather than some other model or
# agent. That is a property of the copilot argv, so it can be checked without a
# token or a real Copilot CLI:
#
#   1. --dry-run prints the invocation, and it names --plugin-dir <repo root>,
#      --agent security-reviewer, the denied and excluded tools, and the prompt
#      only as a placeholder.
#   2. A fake CLI records what run_eval.sh actually executed: the argv, an
#      isolated and empty cwd (not the repo, so EXPECTED.md is out of reach), a
#      scratch COPILOT_HOME, the considerations-mode prompt as the -p value and
#      nothing on stdin. A canned verdict scores `ok`. The token precedence,
#      the caller's own COPILOT_HOME never reaching the CLI, a relative
#      EVAL_PLUGIN_DIR, a CLI failure, a verdict-only row and --only are
#      covered too.
#   3. With no token, the run refuses with exit 2 before any TAP output
#      instead of silently scoring nothing.
#   4. The CI gate in .github/workflows/eval.yml: its "Detect
#      COPILOT_GITHUB_TOKEN" run script, extracted and executed with an empty
#      token, skips (exit 0, present=false) on pull_request — fork and
#      Dependabot PRs get no secrets — and fails (exit 1) on push and
#      workflow_dispatch.
#   5. Break-its: scratch copies of run_eval.sh with one isolation flag, the
#      isolated or empty cwd, the scratch home, the absolute plugin path or the
#      auth refusal removed, the prompt moved, or the token echoed, and scratch
#      copies of eval.yml with one gate branch, the gating or the install
#      broken, each make the pin that guards it fail.
#   6. check_fixtures.sh catches each kind of fixture/EXPECTED.md drift.
#
# The token used here is a fake placeholder with no real token's shape. Exit 0
# when every check passes, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_EVAL="$SCRIPT_DIR/run_eval.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/eval.yml"
FIXTURE="test/fixtures/considerations/token_logging_unmitigated.diff"
VERDICT_ONLY="test/fixtures/considerations/credential_in_consideration_mitigated.diff"
AGENT_ID="security-reviewer"
TOKEN="placeholder-not-a-real-token"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check_eval_invocation.XXXXXX")" || {
  echo "FAIL: could not create a scratch directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

fail=0
check() { # $1=label; remaining args = a test command
  local label="$1"
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label"
    fail=1
  fi
}
contains() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }
q() { printf '%q' "$1"; }

cd "$ROOT_DIR" || exit 1

# --- the fake copilot ----------------------------------------------------------
# Records its argv one element per line (the -p value replaced by <prompt> and
# kept separately in pval), its cwd and how many entries that cwd holds, the
# COPILOT_HOME it saw, whether a token reached it (never the value) and its
# stdin. Prints a fenced JSON verdict built from FAKE_VERDICTS and exits
# FAKE_EXIT.
FAKE="$TMP/fake-copilot"
cat > "$FAKE" <<'FAKE_EOF'
#!/usr/bin/env bash
: > "$FAKE_REC/argv"
prev=""
for a in "$@"; do
  if [ "$prev" = "-p" ]; then
    printf '%s' "$a" > "$FAKE_REC/pval"
    printf '<prompt>\n' >> "$FAKE_REC/argv"
  else
    printf '%s\n' "$a" >> "$FAKE_REC/argv"
  fi
  prev="$a"
done
printf '%s\n' "$0" > "$FAKE_REC/self"
pwd > "$FAKE_REC/pwd"
ls -A | wc -l | tr -d ' ' > "$FAKE_REC/cwd_count"
printf '%s\n' "${COPILOT_HOME-<unset>}" > "$FAKE_REC/home"
if [ -n "${COPILOT_GITHUB_TOKEN:-}${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  echo set > "$FAKE_REC/token"
else
  echo unset > "$FAKE_REC/token"
fi
cat > "$FAKE_REC/stdin"
echo "FAKE-STDERR-LINE" >&2
verdicts="$(printf '%s' "${FAKE_VERDICTS:-unmitigated,mitigated}" | jq -R 'split(",") | map({consideration: "c", status: .})')"
printf '```json\n'
jq -n --argjson v "$verdicts" '{findings: [{severity: "critical", file: "app/users.py", line: 12, vulnerability_class: "injection", cwe: ["CWE-89"], owasp: ["A03:2021"], description: "fake", remediation: "fake", confidence: "high"}], consideration_verdicts: $v}'
printf '```\n'
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$FAKE"

# run_case <name> [VAR=value ...] -- <run_eval args>
# Runs $RUNNER under the fake CLI with every auth variable cleared, then the
# given assignments, feeding a sentinel on stdin. Leaves $TMP/$TAG/<name>.out,
# .rc, the fake's records in rec-<name>/ and the logs in logs-<name>/.
run_case() {
  local name="$1"
  shift
  local envs=()
  # A broken copy lives outside the repo, so point it back at this plugin
  # first; a case's own assignments come later and win.
  if [ "$RUNNER" != "$RUN_EVAL" ]; then
    envs+=("EVAL_PLUGIN_DIR=$ROOT_DIR")
  fi
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    envs+=("$1")
    shift
  done
  [ $# -gt 0 ] && shift
  mkdir -p "$TMP/$TAG/rec-$name" "$TMP/$TAG/tmp-$name"
  printf 'STDIN-SENTINEL\n' | env -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN \
    -u EVAL_COPILOT_LOGIN -u COPILOT_HOME -u EVAL_AGENT -u EVAL_PLUGIN_DIR \
    COPILOT_CLI="$FAKE" FAKE_REC="$TMP/$TAG/rec-$name" LOG_DIR="$TMP/$TAG/logs-$name" \
    TMPDIR="$TMP/$TAG/tmp-$name" ${envs[@]+"${envs[@]}"} \
    bash "$RUNNER" "$@" > "$TMP/$TAG/$name.out" 2>&1
  echo "$?" > "$TMP/$TAG/$name.rc"
}
rc_is() { test "$(cat "$TMP/$TAG/$1.rc" 2>/dev/null)" = "$2"; }
out() { printf '%s' "$TMP/$TAG/$1.out"; }
rec() { printf '%s' "$TMP/$TAG/rec-$1/$2"; }

# pins: sections 1-3 against $RUNNER, results under $TMP/$TAG.
pins() {
  mkdir -p "$TMP/$TAG"

  # --- 1. dry-run prints the exact invocation ---------------------------------
  run_case dry COPILOT_CLI=/nonexistent/copilot -- --dry-run --fixture "$FIXTURE"
  local inv="$TMP/$TAG/dry.inv"
  grep '^# invocation:' "$(out dry)" > "$inv" || true

  check "dry-run needs no token and no CLI (exit 0)"  rc_is dry 0
  check "dry-run prints an invocation line"           test -s "$inv"
  check "the invocation sets a scratch COPILOT_HOME"  contains "$inv" "# invocation: COPILOT_HOME=<scratch dir> "
  check "the invocation loads this repo's plugin"     contains "$inv" "--plugin-dir $(q "$ROOT_DIR") "
  check "the invocation selects the plugin agent"     contains "$inv" "--agent $AGENT_ID "
  check "the invocation denies the shell, write and read tools" contains "$inv" "$(q '--deny-tool=shell, write, read') "
  check "the invocation excludes the built-in file, shell and web tools" \
    contains "$inv" "$(q '--excluded-tools=bash, edit, view, grep, glob, web_fetch, web_search') "
  check "the invocation disables the built-in MCP servers" contains "$inv" " --disable-builtin-mcps "
  check "the invocation skips custom instructions"    contains "$inv" " --no-custom-instructions "
  check "the invocation disables ask_user"            contains "$inv" " --no-ask-user "
  check "the invocation is silent"                    contains "$inv" " -s -p <prompt>"
  check "the invocation passes the prompt with -p, last" grep -q ' -p <prompt>$' "$inv"
  check "the invocation grants no blanket permission" lacks "$inv" "--allow"
  check "the invocation never sets --yolo"            lacks "$inv" "--yolo"
  check "the invocation is not Claude Code's"         lacks "$inv" "claude -p"
  check "the invocation carries no Claude Code flag"  lacks "$inv" "--disallowedTools"
  check "the fixture text is not in the invocation"   lacks "$inv" "request.args"
  check "dry-run reports its auth mode"               contains "$(out dry)" "# auth: dry-run"
  check "the plan, invocation and auth lines are in order" \
    test "$(grep -E '^(1\.\.|# invocation:|# auth:)' "$(out dry)" | cut -c1-6 | tr '\n' '|')" = "1..1|# invo|# auth|"

  # --- 2. a fake CLI records what was really executed -------------------------
  run_case tok "COPILOT_GITHUB_TOKEN=$TOKEN" -- --fixture "$FIXTURE"
  local argv
  argv="$(rec tok argv)"
  check "a canned verdict scores ok (exit 0)"         rc_is tok 0
  check "the TAP line is ok"                          contains "$(out tok)" "ok 1 - considerations/token_logging_unmitigated.diff"
  check "a token in COPILOT_GITHUB_TOKEN is accepted" contains "$(out tok)" "# auth: api-token (COPILOT_GITHUB_TOKEN)"
  check "the fake CLI is what ran"                    test "$(cat "$(rec tok self)" 2>/dev/null)" = "$FAKE"
  check "the CLI received --agent $AGENT_ID"          test "$(grep -A1 -xF -- '--agent' "$argv" 2>/dev/null | sed -n 2p)" = "$AGENT_ID"
  check "the CLI received --plugin-dir <repo root>"   test "$(grep -A1 -xF -- '--plugin-dir' "$argv" 2>/dev/null | sed -n 2p)" = "$ROOT_DIR"
  check "the CLI received the deny flag"              grep -qxF -- '--deny-tool=shell, write, read' "$argv"
  check "the CLI received the exclude flag"           grep -qxF -- '--excluded-tools=bash, edit, view, grep, glob, web_fetch, web_search' "$argv"
  check "the -p value is the last argument"           test "$(tail -n 2 "$argv" 2>/dev/null | tr '\n' '|')" = "-p|<prompt>|"
  # W2278: the agent's one accepted tag, whole line and first line; a bare
  # `mode:` line or the slash-less spelling is not a tag.
  check "the prompt is in considerations mode"        grep -qxF '/security-review invocation, mode: considerations' "$(rec tok pval)"
  check "the prompt opens with the tag"               test "$(head -n 1 "$(rec tok pval)" 2>/dev/null)" = '/security-review invocation, mode: considerations'
  check "the full_file prompt opens with the tag"     contains "$RUNNER" "printf '/security-review invocation, mode: full_file\n\n'"
  check "the prompt carries the considerations list"  contains "$(rec tok pval)" "- $(head -n 1 test/fixtures/considerations/token_logging_unmitigated.considerations)"
  check "the prompt carries the diff"                 contains "$(rec tok pval)" "$(grep -m1 '^+' "$FIXTURE")"
  check "the CLI read nothing on stdin"               test ! -s "$(rec tok stdin)"
  check "the CLI ran outside the repo"                test "$(cat "$(rec tok pwd)" 2>/dev/null)" != "$ROOT_DIR"
  check "the CLI ran from an empty directory"         test "$(cat "$(rec tok cwd_count)" 2>/dev/null)" = "0"
  local home
  home="$(cat "$(rec tok home)" 2>/dev/null)"
  check "COPILOT_HOME is a scratch directory"         test -n "$home" -a "$home" != "<unset>" -a "$home" != "$HOME/.copilot"
  check "COPILOT_HOME is outside the repo and the cwd" test "${home#"$ROOT_DIR"}" = "$home" -a "$home" != "$(cat "$(rec tok pwd)" 2>/dev/null)"
  check "the token reached the CLI"                   test "$(cat "$(rec tok token)" 2>/dev/null)" = "set"
  local rebuilt=""
  if [ -s "$argv" ]; then
    rebuilt="# invocation: COPILOT_HOME=$(q "$home") $(q "$(cat "$(rec tok self)")")"
    local a
    while IFS= read -r a; do
      if [ "$a" = "<prompt>" ]; then rebuilt="$rebuilt <prompt>"; else rebuilt="$rebuilt $(q "$a")"; fi
    done < "$argv"
  fi
  check "the printed invocation is the argv that ran" grep -qxF -- "$rebuilt" "$(out tok)"
  check "the CLI's stderr is kept in err.txt"         grep -rqF FAKE-STDERR-LINE "$TMP/$TAG/logs-tok"
  check "the scratch directories are removed"         test ! -e "$home"
  check "the token never reaches the output"          lacks "$(out tok)" "$TOKEN"
  check "the token never reaches the logs"            test -z "$(grep -rlF -- "$TOKEN" "$TMP/$TAG/logs-tok" 2>/dev/null)"

  # --- 2b. auth precedence, homes, paths, failure, verdict-only rows, --only --
  run_case gh "GH_TOKEN=$TOKEN" -- --fixture "$FIXTURE"
  check "GH_TOKEN alone is accepted"                  contains "$(out gh)" "# auth: api-token (GH_TOKEN)"
  run_case ght "GITHUB_TOKEN=$TOKEN" -- --fixture "$FIXTURE"
  check "GITHUB_TOKEN alone is accepted"              contains "$(out ght)" "# auth: api-token (GITHUB_TOKEN)"
  run_case both "GH_TOKEN=$TOKEN" "COPILOT_GITHUB_TOKEN=$TOKEN" -- --fixture "$FIXTURE"
  check "COPILOT_GITHUB_TOKEN wins over GH_TOKEN"     contains "$(out both)" "# auth: api-token (COPILOT_GITHUB_TOKEN)"
  run_case empty "COPILOT_GITHUB_TOKEN=" -- --fixture "$FIXTURE"
  check "an empty token counts as none (exit 2)"      rc_is empty 2
  mkdir -p "$TMP/$TAG/caller-home"
  run_case callerhome "COPILOT_GITHUB_TOKEN=$TOKEN" "COPILOT_HOME=$TMP/$TAG/caller-home" -- --fixture "$FIXTURE"
  check "the caller's own COPILOT_HOME never reaches the CLI" \
    test "$(cat "$(rec callerhome home)" 2>/dev/null)" != "$TMP/$TAG/caller-home" -a -s "$(rec callerhome home)"
  run_case login EVAL_COPILOT_LOGIN=1 -- --fixture "$FIXTURE"
  check "a stored login is not auth (exit 2)"         rc_is login 2
  run_case relplugin "COPILOT_GITHUB_TOKEN=$TOKEN" EVAL_PLUGIN_DIR=. -- --fixture "$FIXTURE"
  check "a relative EVAL_PLUGIN_DIR reaches the CLI as an absolute path" \
    test "$(grep -A1 -xF -- '--plugin-dir' "$(rec relplugin argv)" 2>/dev/null | sed -n 2p)" = "$ROOT_DIR"
  run_case clifail "COPILOT_GITHUB_TOKEN=$TOKEN" FAKE_EXIT=1 -- --fixture "$FIXTURE"
  check "a CLI failure fails the fixture (exit 1)"    rc_is clifail 1
  check "a CLI failure is reported as such"           contains "$(out clifail)" "agent invocation failed"
  run_case vonly "COPILOT_GITHUB_TOKEN=$TOKEN" FAKE_VERDICTS=mitigated,mitigated -- --fixture "$VERDICT_ONLY"
  check "a verdict-only row parses with U and scores ok" contains "$(out vonly)" "ok 1 - considerations/credential_in_consideration_mitigated.diff (considerations: mitigated,mitigated (U))"
  local ncons
  ncons="$(find test/fixtures/considerations -type f -name '*.diff' | wc -l | tr -d ' ')"
  run_case only COPILOT_CLI=/nonexistent/copilot -- --dry-run --only considerations/
  check "--only considerations/ keeps exactly the considerations rows" contains "$(out only)" "1..$ncons"
  run_case nomatch COPILOT_CLI=/nonexistent/copilot -- --dry-run --only no-such-prefix/
  check "--only with no match exits 2"                rc_is nomatch 2

  # --- 3. no token refuses ----------------------------------------------------
  run_case noauth -- --fixture "$FIXTURE"
  check "no token exits 2"                            rc_is noauth 2
  check "the refusal names COPILOT_GITHUB_TOKEN"      contains "$(out noauth)" "no Copilot auth: export COPILOT_GITHUB_TOKEN"
  check "the refusal comes before any TAP output"     lacks "$(out noauth)" "TAP version"
  check "the refusal never runs the CLI"              test ! -e "$(rec noauth argv)"
}

TAG=main
RUNNER="$RUN_EVAL"
pins

# --- 4. the CI token gate: skip on pull_request, fail on main ------------------
# gate_pins <workflow> <tag>: extract the "Detect COPILOT_GITHUB_TOKEN" step's
# `run: |` block (everything indented deeper than `run:`) and execute it as
# GitHub would, with a temp GITHUB_OUTPUT and no token; then pin the install,
# the Node version and the gating.
gate_pins() {
  local wf="$1" g="$TMP/gate-$2"
  mkdir -p "$g"
  awk '
    /- name: Detect COPILOT_GITHUB_TOKEN$/ { in_step = 1; next }
    in_step && !in_run && /^ +run: \|$/ { in_run = 1; match($0, /^ +/); ind = RLENGTH; next }
    in_run {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      match($0, /^ */)
      if (RLENGTH <= ind) exit
      print substr($0, ind + 3)
    }
  ' "$wf" > "$g/detect.sh"

  gate() { # $1=event name -> prints "<exit code> <GITHUB_OUTPUT contents>"
    : > "$g/gh_output"
    env -u COPILOT_GITHUB_TOKEN COPILOT_GITHUB_TOKEN="" EVENT_NAME="$1" GITHUB_OUTPUT="$g/gh_output" \
      bash "$g/detect.sh" > "$g/gate-$1.out" 2>&1
    printf '%s %s' "$?" "$(tr -d '\n' < "$g/gh_output")"
  }
  check "the CI token-gate script was extracted"    contains "$g/detect.sh" 'EVENT_NAME'
  check "pull_request without a token skips"        test "$(gate pull_request)" = "0 present=false"
  check "the PR skip emits a notice"                contains "$g/gate-pull_request.out" "::notice title=Agent eval skipped::"
  check "push without a token fails"                test "$(gate push)" = "1 "
  check "the push failure emits an error"           contains "$g/gate-push.out" "::error title=Agent eval cannot run::"
  check "workflow_dispatch without a token fails"   test "$(gate workflow_dispatch)" = "1 "
  : > "$g/gh_output"
  COPILOT_GITHUB_TOKEN="$TOKEN" EVENT_NAME=push GITHUB_OUTPUT="$g/gh_output" \
    bash "$g/detect.sh" > "$g/gate-token.out" 2>&1
  check "a configured token runs the eval"          test "$? $(tr -d '\n' < "$g/gh_output")" = "0 present=true"
  check "the gate never prints the token"           lacks "$g/gate-token.out" "$TOKEN"
  check "CI installs Copilot CLI"                   contains "$wf" "npm install -g @github/copilot"
  check "CI does not install Claude Code"           lacks "$wf" "@anthropic-ai/claude-code"
  check "CI uses Node 22"                           contains "$wf" "node-version: '22'"
  check "CI gates the install and the eval on the token" \
    test "$(grep -c "if: steps.token.outputs.present == 'true'" "$wf")" = "2"
  check "CI runs the invocation check"              contains "$wf" "run: bash scripts/check_eval_invocation.sh"
  check "CI runs the fixture parity check"          contains "$wf" "run: bash scripts/check_fixtures.sh"
  check "eval.yml carries no port TODO"             lacks "$wf" "TODO(copilot-port)"
}
gate_pins "$WORKFLOW" main

# --- 5. break-its: each broken copy of run_eval.sh fails its pin ---------------
# break_it <name> <awk program> <label that must FAIL>...
# Writes a copy of run_eval.sh edited by the awk program, checks the edit took
# (the copy differs), runs pins against it and requires every named label to
# come back FAIL.
break_it() {
  local name="$1" prog="$2"
  shift 2
  mkdir -p "$TMP/brk-$name/scripts"
  local copy="$TMP/brk-$name/scripts/run_eval.sh"
  awk "$prog" "$RUN_EVAL" > "$copy"
  if cmp -s "$copy" "$RUN_EVAL"; then
    echo "FAIL: break-it $name: the edit did not take"
    fail=1
    return
  fi
  ( TAG="brk-$name"; RUNNER="$copy"; fail=0; pins ) > "$TMP/brk-$name.out" 2>&1
  # The copy must still run: a crash would fail every pin for the wrong reason.
  check "break-it $name: the broken copy still runs" grep -qxF -- "ok: dry-run prints an invocation line" "$TMP/brk-$name.out"
  local label
  for label in "$@"; do
    check "break-it $name: '$label' fails" grep -qxF -- "FAIL: $label" "$TMP/brk-$name.out"
  done
}

break_it no-agent '!/^    --agent "\$AGENT"$/' \
  "the invocation selects the plugin agent" "the CLI received --agent $AGENT_ID"
break_it no-plugin-dir '!/^    --plugin-dir "\$PLUGIN_DIR"$/' \
  "the invocation loads this repo's plugin" "the CLI received --plugin-dir <repo root>"
break_it no-deny '!/^    --deny-tool="\$DENY_TOOLS"$/' \
  "the invocation denies the shell, write and read tools" "the CLI received the deny flag"
break_it no-cwd '{ sub(/cd "\$WORK_DIR\/cwd" \|\| exit 1/, ":") } { print }' \
  "the CLI ran outside the repo"
break_it no-scratch-home '/export COPILOT_HOME="\$SCRATCH_HOME"/ { next } { print }' \
  "COPILOT_HOME is a scratch directory" "the caller's own COPILOT_HOME never reaches the CLI"
break_it stdin-prompt '{ sub(/exec "\$\{COPILOT_ARGV\[@\]\}" -p "\$prompt"/, "printf %s \"$prompt\" | \"${COPILOT_ARGV[@]}\" -p \"\"") } { print }' \
  "the CLI read nothing on stdin" "the prompt is in considerations mode"
break_it no-refusal '{ sub(/^  die "no Copilot auth:.*/, "  AUTH_MODE=none") } { print }' \
  "no token exits 2" "a stored login is not auth (exit 2)" "an empty token counts as none (exit 2)"
break_it echo-token '{ print } /^  printf .# auth: %s.n. "\$AUTH_MODE"$/ { print "  printf \"# token: %s\\n\" \"${COPILOT_GITHUB_TOKEN:-}\"" }' \
  "the token never reaches the output"
break_it no-u-marker '{ sub(/fexp = "U"/, "fexp = \"\"") } { print }' \
  "a verdict-only row parses with U and scores ok"
break_it no-exclude '!/^    --excluded-tools="\$EXCLUDED_TOOLS"$/' \
  "the invocation excludes the built-in file, shell and web tools" "the CLI received the exclude flag"
break_it no-mcp-off '!/^    --disable-builtin-mcps$/' \
  "the invocation disables the built-in MCP servers"
break_it no-instructions-off '!/^    --no-custom-instructions$/' \
  "the invocation skips custom instructions"
break_it no-ask-user-off '!/^    --no-ask-user$/' \
  "the invocation disables ask_user"
break_it not-silent '!/^    -s$/' \
  "the invocation is silent"
break_it cwd-not-empty '{ print } /^    mkdir "\$WORK_DIR\/cwd"$/ { print "    : > \"$WORK_DIR/cwd/planted\"" }' \
  "the CLI ran from an empty directory"
break_it prompt-not-last '{ sub(/-p "\$prompt"$/, "-p \"$prompt\" --extra") } { print }' \
  "the -p value is the last argument"
break_it relative-plugin-dir '!/^  PLUGIN_DIR="\$\(cd "\$PLUGIN_DIR" && pwd\)"$/' \
  "a relative EVAL_PLUGIN_DIR reaches the CLI as an absolute path"
# W2278: the bare `mode:` line and the slash-less spelling each fail the tag pins.
break_it bare-tag '{ sub(/\/security-review invocation, mode: considerations/, "mode: considerations") } { print }' \
  "the prompt is in considerations mode" "the prompt opens with the tag"
break_it slashless-tag '{ sub(/\/security-review invocation, mode: considerations/, "security-review invocation, mode: considerations") } { print }' \
  "the prompt is in considerations mode" "the prompt opens with the tag"
break_it bare-full-file-tag '{ sub(/\/security-review invocation, mode: full_file/, "mode: full_file") } { print }' \
  "the full_file prompt opens with the tag"

# wf_break_it <name> <awk program> <label that must FAIL>...
# The same for a scratch copy of eval.yml, run through gate_pins.
wf_break_it() {
  local name="$1" prog="$2"
  shift 2
  local copy="$TMP/wf-$name.yml"
  awk "$prog" "$WORKFLOW" > "$copy"
  if cmp -s "$copy" "$WORKFLOW"; then
    echo "FAIL: break-it $name: the edit did not take"
    fail=1
    return
  fi
  ( fail=0; gate_pins "$copy" "brk-$name" ) > "$TMP/wf-$name.out" 2>&1
  check "break-it $name: the broken workflow still yields a gate script" \
    grep -qxF -- "ok: the CI token-gate script was extracted" "$TMP/wf-$name.out"
  local label
  for label in "$@"; do
    check "break-it $name: '$label' fails" grep -qxF -- "FAIL: $label" "$TMP/wf-$name.out"
  done
}
wf_break_it wf-no-pr-skip '{ sub(/= "pull_request"/, "= \"never\"") } { print }' \
  "pull_request without a token skips"
wf_break_it wf-no-exit '!/^            exit 1$/' \
  "push without a token fails" "workflow_dispatch without a token fails"
wf_break_it wf-echo-token '{ print } /^          if \[ -n "\$\{COPILOT_GITHUB_TOKEN:-\}" \]; then$/ { print "            echo \"$COPILOT_GITHUB_TOKEN\"" }' \
  "the gate never prints the token"
wf_break_it wf-node-20 "{ sub(/node-version: '22'/, \"node-version: '20'\") } { print }" \
  "CI uses Node 22"
wf_break_it wf-ungated-install '/^      - name: Install Copilot CLI$/ { s = 1 } s && /^        if: / { s = 0; next } { print }' \
  "CI gates the install and the eval on the token"
wf_break_it wf-claude-code '{ sub(/@github\/copilot/, "@anthropic-ai/claude-code") } { print }' \
  "CI installs Copilot CLI" "CI does not install Claude Code"

# --- 6. check_fixtures.sh catches each kind of drift --------------------------
# Each case edits a scratch copy of the tree (scripts/check_fixtures.sh,
# test/fixtures and README.md) and requires the named complaint and exit 1.
fixtures_case() { # $1=name $2=shell snippet run inside the copy $3=expected text
  local d="$TMP/fx-$1"
  mkdir -p "$d/scripts" "$d/test"
  cp "$SCRIPT_DIR/check_fixtures.sh" "$d/scripts/"
  cp -R "$ROOT_DIR/test/fixtures" "$d/test/"
  cp "$ROOT_DIR/README.md" "$d/"
  ( cd "$d" && eval "$2" )
  bash "$d/scripts/check_fixtures.sh" > "$TMP/fx-$1.out" 2>&1
  local rc=$?
  if [ -z "$3" ]; then
    check "check_fixtures: $1 passes" test "$rc" -eq 0
  else
    check "check_fixtures: $1 fails" test "$rc" -eq 1
    check "check_fixtures: $1 is named" contains "$TMP/fx-$1.out" "$3"
  fi
}
E=test/fixtures/EXPECTED.md
fixtures_case unchanged ':' ''
fixtures_case row-deleted "grep -v 'considerations/search_sort_partial.diff' $E > $E.new && mv $E.new $E" \
  "Fixture files with no EXPECTED.md row"
fixtures_case file-deleted "rm test/fixtures/considerations/search_sort_partial.diff test/fixtures/considerations/search_sort_partial.considerations" \
  "EXPECTED.md rows naming a fixture that does not exist"
fixtures_case sidecar-deleted "rm test/fixtures/considerations/search_sort_partial.considerations" \
  "has no considerations/search_sort_partial.considerations sidecar"
fixtures_case verdict-count "sed 's/CONSIDERATIONS partial,mitigated AND finding/CONSIDERATIONS partial AND finding/' $E > $E.new && mv $E.new $E" \
  "lists 1 verdict(s) but considerations/search_sort_partial.considerations has 2"
fixtures_case readme-count "printf 'Run bash scripts/run_eval.sh (72 fixtures).\\n' >> README.md" \
  "hardcodes a fixture-count annotation"

if [ "$fail" -ne 0 ]; then
  echo "eval invocation: FAILED"
  exit 1
fi
echo "eval invocation: all checks passed"
