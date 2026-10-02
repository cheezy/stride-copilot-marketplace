#!/usr/bin/env bash
# Tests for the stride-ideation-stridify Step 8.5 preview-and-approval gate,
# the Step 1 --yes / --auto-approve bypass (W1147) and the Step 1 / 1b --batch
# mode (W2193) documented in skills/stride-ideation-stridify/SKILL.md. The platform question UI is
# only available inside a live Copilot CLI session, so this test embeds a
# reference shell implementation of the documented flag parse + preview render
# + gate and exercises it against a fixture batch JSON. The human approve /
# decline answer is injected as a parameter (standing in for the prompt result).
#
# The reference implementations below MUST stay consistent with Step 1 and
# Step 8.5 in skills/stride-ideation-stridify/SKILL.md. If you edit one, edit
# both — this test exists to prevent the doc and the on-the-wire behavior from
# drifting apart. A PowerShell mirror lives at lib/test-stridify-preview.ps1.
#
# Run:
#   ./lib/test-stridify-preview.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

PASS=0
FAIL=0
TMP=""

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

TMP="$(mktemp -d)"

pass() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
fail() {
  FAIL=$(( FAIL + 1 ))
  printf 'FAIL  %s\n' "$1"
  if [ "${2:-}" != "" ]; then
    printf '      %s\n' "$2"
  fi
}

# --- reference --yes / --auto-approve parser -------------------------------
#
# Mirrors SKILL.md Step 1. --yes and --auto-approve are bare boolean tokens
# (no value form). Prints two lines: line 1 = AUTO_APPROVE (true|false),
# line 2 = the trimmed remaining arguments.

parse_yes_flag() {
  local args="$1"
  local yes=false
  local out=""
  # shellcheck disable=SC2206
  local toks=( $args )
  local t
  for t in "${toks[@]}"; do
    case "$t" in
      --yes|--auto-approve) yes=true ;;
      *) out="${out:+$out }$t" ;;
    esac
  done
  printf '%s\n%s\n' "$yes" "$out"
}

# --- reference --batch parser ------------------------------------------------
#
# Mirrors SKILL.md Step 1's --batch rules. Prints one line:
#   batch=<path>|yes=<true|false>|err=<usage|goal|doc|>|rest=<remainder>
# err=usage: --batch with no value (bare, `--batch=`, or followed by a flag),
#            or neither --batch nor a doc path; err=goal: --batch with --goal;
# err=doc: --batch with a requirements-doc path left over.

parse_batch_args() {
  # shellcheck disable=SC2206
  local toks=( $1 )
  local batch="" have_batch=false goal="" yes=false rest="" err="" i=0 t
  while [ "$i" -lt "${#toks[@]}" ]; do
    t="${toks[$i]}"
    case "$t" in
      --batch)
        have_batch=true
        if [ $(( i + 1 )) -lt "${#toks[@]}" ] && [ "${toks[$(( i + 1 ))]#--}" = "${toks[$(( i + 1 ))]}" ]; then
          batch="${toks[$(( i + 1 ))]}"; i=$(( i + 1 ))
        else
          err=usage
        fi ;;
      --batch=*) have_batch=true; batch="${t#--batch=}"; [ -n "$batch" ] || err=usage ;;
      --goal) goal="${toks[$(( i + 1 ))]:-}"; i=$(( i + 1 )) ;;
      --goal=*) goal="${t#--goal=}" ;;
      --yes|--auto-approve) yes=true ;;
      *) rest="${rest:+$rest }$t" ;;
    esac
    i=$(( i + 1 ))
  done
  if [ -z "$err" ]; then
    if [ "$have_batch" = true ] && [ -n "$goal" ]; then err=goal
    elif [ "$have_batch" = true ] && [ -n "$rest" ]; then err=doc
    elif [ "$have_batch" = false ] && [ -z "$rest" ]; then err=usage
    fi
  fi
  printf 'batch=%s|yes=%s|err=%s|rest=%s\n' "$batch" "$yes" "$err" "$rest"
}

# --- reference preview render ----------------------------------------------
#
# Mirrors SKILL.md Step 8.5a. Reads ONLY the on-disk batch JSON (no auth
# material) and prints the goal/task tree + cross-goal claim order.

render_preview() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fp:
    data = json.load(fp)

goals = data.get("goals", [])
notes = data.get("decomposition_notes", "")

print()
print("Goals and tasks to be created:")
print()
for goal in goals:
    title = goal.get("title", "(no title)")
    tasks = goal.get("tasks", []) or []
    n = len(tasks)
    print(f"  Goal: {title}  ({n} task{'s' if n != 1 else ''})")
    for task in tasks:
        print(f"    - {task.get('title', '(no title)')}")
print()
if notes:
    print("Cross-goal claim order:")
    print(f"  {notes}")
    print()
PY
}

# --- POST stub + sentinel: confirm whether POST is reached ------------------
#
# The real Step 9 POST is never called in this test. post_stub stands in for
# "control reached the POST"; it writes a sentinel file the assertions check.

post_stub() { echo "POST_ATTEMPTED" > "$TMP/post_was_attempted"; }
post_was_attempted() { [ -f "$TMP/post_was_attempted" ]; }
reset_post_sentinel() { rm -f "$TMP/post_was_attempted"; }

# --- reference preview + gate ----------------------------------------------
#
# Mirrors SKILL.md Step 8.5 a/b/c. Args:
#   <batch-path> <auto-approve:true|false> <answer:approve|decline>
# Always renders the preview. On bypass (auto=true) or an explicit approve, it
# calls post_stub (proceed to Step 9). On decline it prints the clean-stop
# message and returns 10 WITHOUT touching the on-disk JSON or calling POST.

render_and_gate() {
  local batch="$1" auto="$2" answer="$3"
  render_preview "$batch"
  if [ "$auto" = "true" ]; then
    post_stub        # 8.5b bypass: straight to Step 9
    return 0
  fi
  case "$answer" in
    approve)
      post_stub      # 8.5c approval: proceed to Step 9
      return 0
      ;;
    *)
      # 8.5c decline: clean stop, no POST, JSON untouched. Real impl exit 0.
      echo "stride-ideation: declined. The batch JSON is on disk at $batch; no POST was attempted."
      echo "Ship it later, unchanged, by activating stride-ideation-stridify with: --batch \"$batch\""
      return 10
      ;;
  esac
}

# === fixture: a multi-goal batch JSON with cross-goal claim order ==========

BATCH="$TMP/2026-05-12T120000-fixture-stride-batch.json"
cat > "$BATCH" <<'EOF'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "decomposition_notes": "Claim Goal A (data layer) first; Goal B (UI) depends on A's API surface.",
  "goals": [
    {
      "title": "Goal A — data layer",
      "type": "goal",
      "tasks": [
        { "title": "Create the schema migration" },
        { "title": "Add the context module" }
      ]
    },
    {
      "title": "Goal B — UI layer",
      "type": "goal",
      "tasks": [
        { "title": "Wire the LiveView" }
      ]
    }
  ]
}
EOF

BATCH_SHA_BEFORE="$(shasum -a 256 "$BATCH" | awk '{print $1}')"

# === case 1: --yes / --auto-approve parse (both forms + absence) ===========

y_yes="$(parse_yes_flag "--yes /path/to/doc.md")"
y_auto="$(parse_yes_flag "--auto-approve /path/to/doc.md")"
y_none="$(parse_yes_flag "/path/to/doc.md")"

if [ "$(printf '%s' "$y_yes" | sed -n 1p)" = "true" ] \
   && [ "$(printf '%s' "$y_auto" | sed -n 1p)" = "true" ] \
   && [ "$(printf '%s' "$y_none" | sed -n 1p)" = "false" ]; then
  pass "case 1: --yes and --auto-approve set bypass=true; absence leaves bypass=false (AC3)"
else
  fail "case 1: bypass flag parse wrong" \
    "yes=$(printf '%s' "$y_yes" | sed -n 1p) auto=$(printf '%s' "$y_auto" | sed -n 1p) none=$(printf '%s' "$y_none" | sed -n 1p)"
fi

if [ "$(printf '%s' "$y_yes" | sed -n 2p)" = "/path/to/doc.md" ] \
   && [ "$(printf '%s' "$y_none" | sed -n 2p)" = "/path/to/doc.md" ]; then
  pass "case 1: the flag token is consumed and REQUIREMENTS_PATH remainder is preserved"
else
  fail "case 1: remainder wrong after flag consumption" \
    "yes_rem=$(printf '%s' "$y_yes" | sed -n 2p) none_rem=$(printf '%s' "$y_none" | sed -n 2p)"
fi

# === case 2: bypass path reaches POST without an approval prompt (AC3) ======

reset_post_sentinel
render_and_gate "$BATCH" true "" >"$TMP/run_bypass.log" 2>&1
rc_bypass=$?
if [ "$rc_bypass" -eq 0 ] && post_was_attempted; then
  pass "case 2: --yes bypass proceeds to POST (sentinel set, rc 0)"
else
  fail "case 2: bypass did not reach POST" "rc=$rc_bypass"
fi
if ! grep -qiF "declined" "$TMP/run_bypass.log"; then
  pass "case 2: bypass path prints no decline / prompt text"
else
  fail "case 2: bypass path unexpectedly printed decline text"
fi

# === case 3: decline path does NOT POST and leaves JSON on disk (AC1/AC4) ===

reset_post_sentinel
render_and_gate "$BATCH" false decline >"$TMP/run_decline.log" 2>&1
rc_decline=$?
if [ "$rc_decline" -eq 10 ] && ! post_was_attempted; then
  pass "case 3: decline does NOT attempt the POST (no sentinel)"
else
  fail "case 3: decline attempted the POST (regression)" "rc=$rc_decline"
fi
if [ -f "$BATCH" ]; then
  pass "case 3: declined batch JSON remains on disk"
else
  fail "case 3: declined batch JSON was removed (regression)"
fi
BATCH_SHA_AFTER="$(shasum -a 256 "$BATCH" | awk '{print $1}')"
if [ "$BATCH_SHA_BEFORE" = "$BATCH_SHA_AFTER" ]; then
  pass "case 3: declined batch JSON is byte-for-byte unchanged (recovery artifact preserved)"
else
  fail "case 3: declined batch JSON was rewritten (pitfall violated)"
fi
if grep -qF "no POST was attempted" "$TMP/run_decline.log"; then
  pass "case 3: decline message states the POST was not attempted"
else
  fail "case 3: decline message missing 'no POST was attempted'"
fi
if grep -qF -- "--batch \"$BATCH\"" "$TMP/run_decline.log"; then
  pass "case 3: decline message names the --batch form for this file"
else
  fail "case 3: decline message does not name --batch"
fi

# === case 4: approve path proceeds to POST (AC2) ===========================

reset_post_sentinel
render_and_gate "$BATCH" false approve >"$TMP/run_approve.log" 2>&1
rc_approve=$?
if [ "$rc_approve" -eq 0 ] && post_was_attempted; then
  pass "case 4: explicit approval proceeds to POST (sentinel set, rc 0)"
else
  fail "case 4: approval did not reach POST" "rc=$rc_approve"
fi

# === case 5: render lists every goal and its task count (AC1) ==============

render_preview "$BATCH" > "$TMP/preview.txt" 2>&1
if grep -qF "Goal: Goal A — data layer  (2 tasks)" "$TMP/preview.txt" \
   && grep -qF "Goal: Goal B — UI layer  (1 task)" "$TMP/preview.txt"; then
  pass "case 5: preview lists each goal with its task count (singular/plural correct)"
else
  fail "case 5: goal/task-count render wrong" "$(cat "$TMP/preview.txt")"
fi
if grep -qF -- "- Create the schema migration" "$TMP/preview.txt" \
   && grep -qF -- "- Add the context module" "$TMP/preview.txt" \
   && grep -qF -- "- Wire the LiveView" "$TMP/preview.txt"; then
  pass "case 5: preview lists every task title"
else
  fail "case 5: task titles missing from render" "$(cat "$TMP/preview.txt")"
fi

# === case 6: render shows cross-goal claim order from decomposition_notes (AC1, edge case) ===

if grep -qF "Cross-goal claim order:" "$TMP/preview.txt" \
   && grep -qF "Claim Goal A (data layer) first" "$TMP/preview.txt"; then
  pass "case 6: preview shows cross-goal claim order from decomposition_notes"
else
  fail "case 6: cross-goal claim order missing from render" "$(cat "$TMP/preview.txt")"
fi

# === case 7: --goal scoped (single-goal) batch renders the one goal (edge case) ===

SINGLE="$TMP/2026-05-12T120000-fixture-kanban-app-stride-batch.json"
cat > "$SINGLE" <<'EOF'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
  "decomposition_notes": "Single-goal shape, no cross-goal coordination.",
  "goals": [
    {
      "title": "Kanban app — review queue",
      "type": "goal",
      "tasks": [
        { "title": "Add the review column" }
      ]
    }
  ]
}
EOF
render_preview "$SINGLE" > "$TMP/preview_single.txt" 2>&1
if grep -qF "Goal: Kanban app — review queue  (1 task)" "$TMP/preview_single.txt" \
   && [ "$(grep -cF 'Goal: ' "$TMP/preview_single.txt")" = "1" ]; then
  pass "case 7: --goal scoped batch renders exactly the single scoped goal"
else
  fail "case 7: single-goal render wrong" "$(cat "$TMP/preview_single.txt")"
fi

# === case 8: pitfall — no token / auth material in any gate output =========

if grep -qE 'stride_(dev|prod)_|Bearer |Authorization:' \
     "$TMP/preview.txt" "$TMP/run_bypass.log" "$TMP/run_decline.log" "$TMP/run_approve.log"; then
  fail "case 8: gate output contains potential auth material (pitfall violated)"
else
  pass "case 8: no Bearer/token/Authorization strings in preview or gate output (pitfall avoided)"
fi

# === cases 9-14: --batch parse ==============================================

expect_parse() {
  local label="$1" args="$2" want="$3" got
  got="$(parse_batch_args "$args")"
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label" "got: $got"; fi
}
expect_parse "case 9: --batch <path> selects batch mode" "--batch docs/x-stride-batch.json" "batch=docs/x-stride-batch.json|yes=false|err=|rest="
expect_parse "case 10: --batch=<path> splits on the first = only" "--batch=docs/a=b.json" "batch=docs/a=b.json|yes=false|err=|rest="
expect_parse "case 11a: a bare trailing --batch is a usage error" "--batch" "batch=|yes=false|err=usage|rest="
expect_parse "case 11b: --batch= with no value is a usage error" "--batch=" "batch=|yes=false|err=usage|rest="
expect_parse "case 11c: --batch followed by a flag never takes the flag as its path" "--batch --yes" "batch=|yes=true|err=usage|rest="
expect_parse "case 12: --batch together with --goal is rejected" "--batch b.json --goal 2" "batch=b.json|yes=false|err=goal|rest="
expect_parse "case 12b: --goal=<v> before --batch=<v> is rejected too" "--goal=2 --batch=b.json" "batch=b.json|yes=false|err=goal|rest="
expect_parse "case 13: --batch with a requirements-doc path left over is rejected" "--batch b.json docs/x-requirements.md" "batch=b.json|yes=false|err=doc|rest=docs/x-requirements.md"
expect_parse "case 14a: --batch --yes keeps the path and sets the bypass" "--batch b.json --yes" "batch=b.json|yes=true|err=|rest="
expect_parse "case 14b: no --batch and no doc path is a usage error" "--yes" "batch=|yes=true|err=usage|rest="

SKILL_MD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills/stride-ideation-stridify/SKILL.md"
if grep -qF 'cannot be combined with --goal' "$SKILL_MD" \
   && grep -qF -- '--batch takes a batch JSON, not a requirements doc' "$SKILL_MD" \
   && grep -qF -- 'or `--batch <path-to-stride-batch.json> [--yes]`' "$SKILL_MD"; then
  pass "case 14c: SKILL.md Step 1 documents the --goal / doc-path rejections and the --batch usage form"
else
  fail "case 14c: SKILL.md Step 1 is missing a --batch rule this test mirrors"
fi

# === cases 15-20: Step 1b validate, then Step 9 ship, against a mocked HTTP layer ===
#
# The real blocks are extracted from SKILL.md (Step 1b's validate block, the
# Step 8.5c decline block and the Step 9 ship block), their '<value of NAME>'
# placeholders filled, and run under bash -u in a scratch git repository with
# a fake curl on PATH — so this exercises the documented commands, not a copy.

PLUGIN_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN="stride_dev_PREVIEW_TEST_TOKEN_0123456789abcdef"
printf -- '- **API URL:** `https://stride.example`\n- **API Token:** `%s`\n' "$TOKEN" > "$TMP/auth.md"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: logs each call, writes FAKE_BODY to -o, prints FAKE_CODE.
echo x >> "$FAKE_LOG"
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; esac
  shift
done
cat > /dev/null
if [ -n "$out" ]; then cp "$FAKE_BODY" "$out"; fi
printf '%s' "${FAKE_CODE:-201}"
EOF
chmod +x "$TMP/bin/curl"
cat > "$TMP/created.json" <<'EOF'
{"success": true, "total": 1, "goals": [
  {"goal": {"id": 1, "identifier": "G77", "title": "Goal A — data layer", "type": "goal"},
   "child_tasks": [{"id": 2, "identifier": "W901", "title": "Create the schema migration"}]}]}
EOF

# extract <marker> <out> <batch-path> — the one bash block containing <marker>.
extract() {
  python3 - "$SKILL_MD" "$1" "$2" "$PLUGIN_ROOT_DIR" "$3" <<'PY2'
import re, sys
md, marker, out, root, batch = sys.argv[1:6]
text = open(md, encoding="utf-8").read()
blocks = [m.group(2) for m in re.finditer(r"^([ \t]*)```bash[ \t]*\n(.*?)^\1```[ \t]*$", text, re.S | re.M)
          if marker in m.group(2)]
if len(blocks) != 1:
    sys.exit("expected one block containing %r, found %d" % (marker, len(blocks)))
body = re.sub(r"(?m)^   ", "", blocks[0])
q = lambda v: "'" + v.replace("'", "'\\''") + "'"
body = body.replace("'<value of PLUGIN_ROOT>'", q(root)).replace("'<value of BATCH_PATH>'", q(batch))
open(out, "w").write(body)
PY2
}

# run_block <name> <block-file> — in the scratch repo, against the fake curl.
run_block() {
  local name="$1" block="$2"
  : > "$TMP/$name.calls"
  ( cd "$REPO" && PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/$name.calls" FAKE_BODY="$TMP/created.json" \
      STRIDE_AUTH_FILE="$TMP/auth.md" TMPDIR="$TMP" bash -u "$block" > "$TMP/$name.out" 2> "$TMP/$name.err" )
  echo "$?" > "$TMP/$name.rc"
}
calls() { grep -c x "$TMP/$1.calls"; }

REPO="$TMP/repo"
mkdir -p "$REPO/docs/ideation"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
cp "$PLUGIN_ROOT_DIR/fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json" "$REPO/docs/ideation/declined-stride-batch.json"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed
HEAD_BEFORE="$(git -C "$REPO" rev-parse HEAD)"
SHIP_BATCH="$REPO/docs/ideation/declined-stride-batch.json"
SHA_BEFORE="$(shasum -a 256 "$SHIP_BATCH" | awk '{print $1}')"

extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b.sh" "$SHIP_BATCH" || exit 1
extract 'lib/ship.sh" "$BATCH_PATH"' "$TMP/step9.sh" "$SHIP_BATCH" || exit 1

run_block v-ok "$TMP/step1b.sh"
if [ "$(cat "$TMP/v-ok.rc")" = 0 ] && [ "$(calls v-ok)" = 0 ]; then
  pass "case 15: Step 1b accepts a valid batch and makes no request"
else
  fail "case 15: Step 1b on a valid batch" "rc=$(cat "$TMP/v-ok.rc") calls=$(calls v-ok) err=$(head -c 300 "$TMP/v-ok.err")"
fi
if grep -qF 'shipping it again creates every goal and task a second time' "$TMP/v-ok.err"; then
  pass "case 15: Step 1b warns that re-shipping a shipped batch duplicates it"
else
  fail "case 15: no duplicate warning"
fi

render_preview "$SHIP_BATCH" > "$TMP/batch-preview.txt" 2>&1
if grep -qF 'Goal: Add a dark mode toggle to the app header' "$TMP/batch-preview.txt" \
   && ! grep -qE 'stride_(dev|prod)_|Bearer ' "$TMP/batch-preview.txt"; then
  pass "case 15b: the --batch file previews its goal titles and no auth material"
else
  fail "case 15b: --batch preview" "$(head -c 300 "$TMP/batch-preview.txt")"
fi
run_block ship-ok "$TMP/step9.sh"
if [ "$(cat "$TMP/ship-ok.rc")" = 0 ] && [ "$(calls ship-ok)" = 1 ] && grep -qF 'G77' "$TMP/ship-ok.out" && grep -qF 'W901' "$TMP/ship-ok.out"; then
  pass "case 16: Step 9 ships the --batch file once through lib/ship.sh and renders the identifiers"
else
  fail "case 16: Step 9 ship" "rc=$(cat "$TMP/ship-ok.rc") calls=$(calls ship-ok) out=$(head -c 300 "$TMP/ship-ok.out") err=$(head -c 300 "$TMP/ship-ok.err")"
fi
if [ "$(shasum -a 256 "$SHIP_BATCH" | awk '{print $1}')" = "$SHA_BEFORE" ] \
   && [ "$(git -C "$REPO" rev-parse HEAD)" = "$HEAD_BEFORE" ] && [ -z "$(git -C "$REPO" status --porcelain)" ]; then
  pass "case 17: --batch leaves the file byte-identical and creates no commit"
else
  fail "case 17: the --batch run rewrote the file or committed" "$(git -C "$REPO" status --porcelain)"
fi

python3 - "$SHIP_BATCH" "$REPO/bad-stride-batch.json" <<'PY2'
import json, sys
doc = json.load(open(sys.argv[1]))
del doc["goals"][0]["tasks"][0]["type"]
json.dump(doc, open(sys.argv[2], "w"))
PY2
extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b-bad.sh" "$REPO/bad-stride-batch.json" || exit 1
run_block v-bad "$TMP/step1b-bad.sh"
if [ "$(cat "$TMP/v-bad.rc")" = 1 ] && [ "$(calls v-bad)" = 0 ] && grep -qF "goals[0].tasks[0] is missing required field 'type'" "$TMP/v-bad.err"; then
  pass "case 18: an invalid batch fails validation in Step 1b before any request"
else
  fail "case 18: invalid batch" "rc=$(cat "$TMP/v-bad.rc") calls=$(calls v-bad) err=$(head -c 300 "$TMP/v-bad.err")"
fi

python3 - "$SHIP_BATCH" "$REPO/token-stride-batch.json" "$TOKEN" <<'PY2'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["decomposition_notes"] = "pasted: " + sys.argv[3]
json.dump(doc, open(sys.argv[2], "w"))
PY2
extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b-token.sh" "$REPO/token-stride-batch.json" || exit 1
run_block v-token "$TMP/step1b-token.sh"
if [ "$(cat "$TMP/v-token.rc")" = 1 ] && [ "$(calls v-token)" = 0 ] && grep -qF 'contains the configured Stride API token' "$TMP/v-token.err" \
   && ! grep -qF "$TOKEN" "$TMP/v-token.out" "$TMP/v-token.err"; then
  pass "case 19: a batch carrying the API token is refused in Step 1b without printing it"
else
  fail "case 19: token batch" "rc=$(cat "$TMP/v-token.rc") calls=$(calls v-token)"
fi

extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b-missing.sh" "$REPO/nope-stride-batch.json" || exit 1
run_block v-missing "$TMP/step1b-missing.sh"
extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b-dash.sh" "-x.json" || exit 1
run_block v-dash "$TMP/step1b-dash.sh"
if [ "$(cat "$TMP/v-missing.rc")" = 1 ] && grep -qF 'batch JSON not found at' "$TMP/v-missing.err" \
   && [ "$(cat "$TMP/v-dash.rc")" = 1 ] && grep -qF "starts with '-'" "$TMP/v-dash.err"; then
  pass "case 20: a missing batch path and a path starting with '-' both stop Step 1b"
else
  fail "case 20: missing / dash path" "missing rc=$(cat "$TMP/v-missing.rc") dash rc=$(cat "$TMP/v-dash.rc")"
fi

python3 - "$SHIP_BATCH" "$REPO/bare-stride-batch.json" <<'PY2'
import json, sys
doc = json.load(open(sys.argv[1]))
for k in ("source_spec", "source_spec_sha256", "decomposition_notes"):
    doc.pop(k, None)
json.dump(doc, open(sys.argv[2], "w"))
PY2
extract 'validate_batch.py" "$BATCH_PATH" || exit 1' "$TMP/step1b-bare.sh" "$REPO/bare-stride-batch.json" || exit 1
run_block v-bare "$TMP/step1b-bare.sh"
if [ "$(cat "$TMP/v-bare.rc")" = 0 ]; then
  pass "case 20b: a batch without the local audit fields passes Step 1b"
else
  fail "case 20b: bare batch" "err=$(head -c 300 "$TMP/v-bare.err")"
fi

extract 'echo "stride-ideation: declined.' "$TMP/decline.sh" "$SHIP_BATCH" || exit 1
run_block decline "$TMP/decline.sh"
if [ "$(cat "$TMP/decline.rc")" = 0 ] && grep -qF -- "--batch \"$SHIP_BATCH\"" "$TMP/decline.err" && grep -qF 'no POST was attempted' "$TMP/decline.err"; then
  pass "case 21: SKILL.md's decline block exits 0 and names --batch for the file"
else
  fail "case 21: decline block" "rc=$(cat "$TMP/decline.rc") err=$(cat "$TMP/decline.err")"
fi

# === summary ==============================================================

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
