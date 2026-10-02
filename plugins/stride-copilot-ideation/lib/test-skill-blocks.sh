#!/usr/bin/env bash
# Tests that every fenced bash block in the two surface skills
# (skills/stride-ideation-ideate/SKILL.md and
# skills/stride-ideation-stridify/SKILL.md) is self-contained: it runs in a
# fresh shell given only the values its "# Carried forward:" line names.
#
# Each block is extracted, its '<value of NAME>' placeholders are filled with
# fixture values (shell-quoted the way the skills tell the model to quote
# them), and it is run with `bash -u` in its own scratch git repository. curl
# is a PATH-prepended fake, so the ship blocks make no network request. The
# static checks then pin the rules the skills state once near their top:
#   - a block that calls an sti_ function sources its helper itself;
#   - a block reads no variable it did not assign (carried-forward values
#     are assigned at the top of the block);
#   - a block body runs in a ( ... ) subshell, so its exit ends only that
#     subshell, never a shared shell;
#   - no <plugin-root> placeholder remains.
#
# Run:
#   ./lib/test-skill-blocks.sh
#
# Exits 0 if all tests pass, non-zero otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# --- fixtures -------------------------------------------------------------------

# A fake value only; the ship blocks never reach a network.
TOKEN="stride_dev_BLOCK_TEST_TOKEN_x7"
cat > "$TMP/auth.md" <<EOF
- **API URL:** \`https://stride.example\`
- **API Token:** \`$TOKEN\`
EOF

mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: answer 201 with a renderable body, whatever was asked.
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift ;; esac
  shift
done
cat > /dev/null
[ -n "$out" ] && printf '%s' '{"success": true, "total": 1, "goals": [{"goal": {"identifier": "G1", "title": "Goal"}, "child_tasks": []}]}' > "$out"
printf '201'
EOF
chmod +x "$TMP/bin/curl"

REQ_NAME="2026-05-12T120000-dark-mode-toggle-requirements.md"
BATCH_NAME="2026-05-12T120000-dark-mode-toggle-stride-batch.json"

# new_sandbox DIR — a scratch git repo holding the fixture requirements doc
# (with a Decomposition seams section), a batch JSON and a draft.
new_sandbox() {
  local d="$1"
  mkdir -p "$d/docs/ideation" "$d/.stride" "$d/tmp"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  { cat "$PLUGIN_ROOT/fixtures/$REQ_NAME"
    printf '\n## Decomposition seams\n\n1. **Kanban app** — owns the JSON contract\n2. **stride plugin** — the adapter\n'
  } > "$d/docs/ideation/$REQ_NAME"
  git -C "$d" add docs/ideation/"$REQ_NAME"
  git -C "$d" commit -q -m fixture
  cp "$PLUGIN_ROOT/fixtures/$BATCH_NAME" "$d/docs/ideation/$BATCH_NAME"
  mkdir -p "$d/tmp/stride_stridify_validate.fixture"
  cp "$PLUGIN_ROOT/fixtures/$BATCH_NAME" "$d/tmp/stride_stridify_validate.fixture/batch.json"
  printf '# draft\n' > "$d/.stride/2026-05-12T103000-dark-mode-toggle-draft.md"
  printf '# requirements\n' > "$d/docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md"
}

# --- extract every block, fill its placeholders ----------------------------------
#
# Pass 1 fills every ", or empty" placeholder with '' (a fresh ideate session,
# no --goal). Pass 2 re-runs each block that has such a placeholder with the
# optional values set (--continue, --goal), so those branches run too.

python3 - "$PLUGIN_ROOT" "$TMP/blocks" <<'PY'
import os, re, sys

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out)

def q(value):
    # The quoting the skills prescribe: single quotes, ' written as '\''.
    return "'" + value.replace("'", "'\\''") + "'"

common = {
    "PLUGIN_ROOT": root,
    "TOPIC": "Dark mode toggle — it's overdue",
    "SESSION_TS": "2026-05-12T103000",
    "SLUG": "dark-mode-toggle",
    "REQUIREMENTS_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-requirements.md",
    "GOAL_ARG": "1",
    "GOAL_INDEX": "1",
    "SOURCE_TS": "2026-05-12T120000",
    "SLUG_FOR_PATH": "dark-mode-toggle",
    "TMP_DIR": "tmp/stride_stridify_validate.fixture",
    "BATCH_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json",
    "DRAFT_PATH": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
    "existing_draft": ".stride/2026-05-12T103000-dark-mode-toggle-draft.md",
}
per_skill = {
    "stride-ideation-ideate": {"TARGET_PATH": "docs/ideation/2026-05-12T103000-dark-mode-toggle-requirements.md"},
    "stride-ideation-stridify": {"TARGET_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-stride-batch.json"},
}

optional = {
    "CONTINUE_PATH": "docs/ideation/2026-05-12T120000-dark-mode-toggle-requirements.md",
    "GOAL_SLUG": "kanban-app",
    "GOAL_ARG": "1",
}

fence = re.compile(r"^([ \t]*)```bash[ \t]*\n(.*?)^\1```[ \t]*$", re.S | re.M)
placeholder = re.compile(r"'<value of ([A-Za-z_]+)(, or empty)?>'")
n = 0
for skill in ("stride-ideation-ideate", "stride-ideation-stridify"):
    path = os.path.join(root, "skills", skill, "SKILL.md")
    text = open(path, encoding="utf-8").read()
    values = dict(common, **per_skill[skill])
    for m in fence.finditer(text):
        indent, body = m.group(1), m.group(2)
        body = "\n".join(line[len(indent):] if line.startswith(indent) else line for line in body.split("\n"))
        line_no = text.count("\n", 0, m.start()) + 1
        def fill(pm):
            name, empty = pm.group(1), pm.group(2)
            return "''" if empty else q(values[name])
        def fill_optional(pm):
            name, empty = pm.group(1), pm.group(2)
            return q(optional[name]) if empty else q(values[name])
        n += 1
        base = os.path.join(out, "%02d" % n)
        open(base + ".label", "w").write("%s:%d" % (skill, line_no))
        open(base + ".raw", "w").write(body)
        open(base + ".sh", "w").write(placeholder.sub(fill, body))
        if ", or empty>" in body:
            opt = os.path.join(out, "%02d-opt" % n)
            open(opt + ".label", "w").write("%s:%d [optional values set]" % (skill, line_no))
            open(opt + ".sh", "w").write(placeholder.sub(fill_optional, body))
PY

BLOCKS="$(ls "$TMP/blocks"/*.raw | wc -l | tr -d ' ')"
OPT_BLOCKS="$(ls "$TMP/blocks"/*-opt.sh | wc -l | tr -d ' ')"
if [ "$OPT_BLOCKS" -ge 6 ]; then
  pass "blocks with optional values also run with them set ($OPT_BLOCKS blocks)"
else
  fail "expected at least 6 blocks with optional values, found $OPT_BLOCKS"
fi
if [ "$BLOCKS" -ge 20 ]; then
  pass "extracted every bash block from both skills ($BLOCKS blocks)"
else
  fail "expected at least 20 bash blocks, found $BLOCKS"
fi

# --- no <plugin-root> placeholder remains ------------------------------------------

if grep -rn 'plugin-root' "$PLUGIN_ROOT/skills" > /dev/null; then
  fail "a <plugin-root> placeholder remains in skills/" "$(grep -rn 'plugin-root' "$PLUGIN_ROOT/skills" | head -3)"
else
  pass "no <plugin-root> placeholder remains in skills/"
fi

# --- per-block static checks and a fresh-shell run --------------------------------

for sh in "$TMP/blocks"/*.sh; do
  base="${sh%.sh}"
  label="$(cat "$base.label")"
  raw="$base.raw"

  # Static checks read the raw block text, so they run once per block (the
  # optional-values pass reruns the same text with different values).
  if [ -f "$raw" ]; then
    # The body runs in a ( ... ) subshell, so an exit never ends a shared shell.
    first="$(grep -v '^[[:space:]]*$' "$raw" | head -n 1)"
    last="$(grep -v '^[[:space:]]*$' "$raw" | tail -n 1)"
    if [ "$first" = "(" ] && [ "$last" = ")" ]; then
      pass "$label: body runs in a ( ... ) subshell"
    else
      fail "$label: body is not wrapped in ( ... )" "first='$first' last='$last'"
    fi

    # A block that calls an sti_ function sources that function's helper itself.
    if grep -qE 'sti_(slugify|slug_from_path|unique_path|resolve_goal|extract_seams|scope_doc_to_seam)\b' "$raw"; then
      if grep -qF '. "$PLUGIN_ROOT/lib/filename.sh"' "$raw"; then pass "$label: sources lib/filename.sh for its sti_ calls"; else fail "$label: calls a filename.sh function without sourcing it"; fi
    fi
    if grep -qE 'sti_draft_[a-z]+' "$raw"; then
      if grep -qF '. "$PLUGIN_ROOT/lib/draft.sh"' "$raw"; then pass "$label: sources lib/draft.sh for its sti_draft_ calls"; else fail "$label: calls a draft.sh function without sourcing it"; fi
    fi

    # Every variable the block reads is assigned in the block itself.
    unassigned="$(python3 - "$raw" <<'PY'
import re, sys
body = open(sys.argv[1]).read()
code = re.sub(r"<<'PY'\n.*?\nPY\n", "\n", body, flags=re.S)        # python heredocs
code = re.sub(r"awk(?: -F'[^']*')? '[^']*'", "awk", code, flags=re.S)  # awk programs
used = set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", code))
assigned = set(re.findall(r"(?:^|[\s;(])([A-Za-z_][A-Za-z0-9_]*)=", code))
env = {"TMPDIR"}
print(" ".join(sorted(used - assigned - env)))
PY
  )"
    if [ -z "$unassigned" ]; then
      pass "$label: reads only variables it assigns"
    else
      fail "$label: reads variables set outside the block" "$unassigned"
    fi
  fi

  # Run it in a fresh bash with nounset on, in its own sandbox.
  box="$base.box"
  new_sandbox "$box"
  ( cd "$box" && env -i PATH="$TMP/bin:$PATH" HOME="$HOME" TMPDIR="$box/tmp" STRIDE_AUTH_FILE="$TMP/auth.md" \
      bash -u "$sh" > "$base.out" 2> "$base.err" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: runs in a fresh shell (exit 0)"
  else
    fail "$label: exited $rc in a fresh shell" "$(head -c 300 "$base.err")"
  fi
  if grep -qE 'unbound variable|command not found' "$base.err"; then
    fail "$label: hit an unbound variable or undefined command" "$(grep -E 'unbound variable|command not found' "$base.err" | head -2)"
  else
    pass "$label: no unbound variable or undefined command"
  fi
  if grep -qF "$TOKEN" "$base.out" "$base.err"; then
    fail "$label: printed the token"
  fi
done

# --- the plugin-root check fails clearly ------------------------------------------

check_block="$(grep -lF 'plugin root OK' "$TMP/blocks"/*.raw | head -n 1)"
python3 - "$check_block" "$TMP/badroot.sh" <<'PY'
import sys
body = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(body.replace("'<value of PLUGIN_ROOT>'", "'/nonexistent/plugin root'"))
PY
bash -u "$TMP/badroot.sh" > "$TMP/badroot.out" 2> "$TMP/badroot.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -qF 'stride-ideation: cannot find the plugin helpers: /nonexistent/plugin root/lib/filename.sh does not exist' "$TMP/badroot.err"; then
  pass "a wrong PLUGIN_ROOT fails non-zero with a clear message"
else
  fail "a wrong PLUGIN_ROOT did not fail clearly" "rc=$rc $(cat "$TMP/badroot.err")"
fi

# --- a failing block does not end a shared shell ----------------------------------

{ cat "$TMP/badroot.sh"; printf '\necho "shell still alive (block status $?)"\n'; } > "$TMP/shared.sh"
out="$(bash "$TMP/shared.sh" 2>/dev/null)"
if [ "$out" = "shell still alive (block status 1)" ]; then
  pass "a failing block returns non-zero without ending a shared shell"
else
  fail "a failing block ended the shared shell" "$out"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
