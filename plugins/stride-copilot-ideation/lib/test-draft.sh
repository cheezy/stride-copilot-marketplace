#!/usr/bin/env bash
# Unit tests for lib/draft.sh — the stride-ideation-ideate intra-session draft
# autosave/resume helpers (W1145). A PowerShell mirror lives at
# lib/test-draft.ps1.
#
# Run:
#   ./lib/test-draft.sh
#
# Exits 0 if all tests pass, non-zero otherwise. Prints a one-line per-test
# status to stdout.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/draft.sh"

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

assert_eq() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$(( PASS + 1 ))
    printf 'PASS  %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 ))
    printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$label" "$expected" "$actual"
  fi
}

ok() { PASS=$(( PASS + 1 )); printf 'PASS  %s\n' "$1"; }
no() { FAIL=$(( FAIL + 1 )); printf 'FAIL  %s\n' "$1"; }

# --- draft_path: deterministic for a given ts+slug ---------------------------

assert_eq "draft_path: <dir>/<ts>-<slug>-draft.md" \
  "$(sti_draft_path .stride 2026-05-12T103000 add-notifications)" \
  ".stride/2026-05-12T103000-add-notifications-draft.md"

assert_eq "draft_path: trailing slash on dir is normalized" \
  "$(sti_draft_path .stride/ 2026-05-12T103000 foo)" \
  ".stride/2026-05-12T103000-foo-draft.md"

P1="$(sti_draft_path "$TMP" 2026-05-12T103000 foo)"
P2="$(sti_draft_path "$TMP" 2026-05-12T103000 foo)"
assert_eq "draft_path: deterministic for a given SESSION_TS+slug" "$P1" "$P2"

BAD="$(sti_draft_path "$TMP" 2026-05-12T103000 2>/dev/null || true)"
if [ -z "$BAD" ]; then
  ok "draft_path: missing slug -> empty stdout + non-zero"
else
  no "draft_path: missing slug leaked output: $BAD"
fi

# --- save then load: round-trips content ------------------------------------

DRAFT="$(sti_draft_path "$TMP/.stride" 2026-05-12T103000 round-trip)"
CONTENT="## Goal
Ship the digest.

## Problem
Approvals rot in inboxes.
__round_state__: 2"

if sti_draft_save "$DRAFT" "$CONTENT"; then
  ok "draft_save: writes the scratch file (and creates .stride/ parent)"
else
  no "draft_save: failed to write"
fi

if [ -f "$DRAFT" ]; then
  ok "draft_save: scratch file exists at the computed path"
else
  no "draft_save: scratch file missing after save"
fi

assert_eq "draft_load: round-trips the saved content byte-for-byte" \
  "$(sti_draft_load "$DRAFT")" "$CONTENT"

# --- exists: predicate on non-empty draft -----------------------------------

if sti_draft_exists "$DRAFT"; then
  ok "draft_exists: true for a non-empty draft"
else
  no "draft_exists: false for a non-empty draft (should be true)"
fi

EMPTY="$(sti_draft_path "$TMP/.stride" 2026-05-12T103000 empty-draft)"
: > "$EMPTY"
if sti_draft_exists "$EMPTY"; then
  no "draft_exists: true for an empty draft (should be false)"
else
  ok "draft_exists: false for an empty/zero-length draft (partial -> fresh)"
fi

if sti_draft_exists "$TMP/.stride/nope-draft.md"; then
  no "draft_exists: true for an absent draft (should be false)"
else
  ok "draft_exists: false for an absent draft"
fi

# --- load: absent file -> non-zero, no crash --------------------------------

LOAD_BAD="$(sti_draft_load "$TMP/.stride/missing-draft.md" 2>/dev/null || true)"
if [ -z "$LOAD_BAD" ]; then
  ok "draft_load: absent file -> empty stdout + non-zero (safe, no crash)"
else
  no "draft_load: absent file leaked output: $LOAD_BAD"
fi

# --- save: mkdir-failure branch returns non-zero, no crash ------------------

BLOCKER="$TMP/blocker"
: > "$BLOCKER"
SAVE_ERR="$(sti_draft_save "$BLOCKER/sub/2026-05-12T103000-x-draft.md" "body" 2>&1 || true)"
if sti_draft_save "$BLOCKER/sub/2026-05-12T103000-x-draft.md" "body" 2>/dev/null; then
  no "draft_save: succeeded despite an unmakeable parent dir (should fail)"
else
  ok "draft_save: returns non-zero when the parent dir cannot be created (no crash)"
fi
if printf '%s' "$SAVE_ERR" | grep -q "cannot create scratch directory"; then
  ok "draft_save: mkdir failure emits a one-line diagnostic to stderr"
else
  no "draft_save: mkdir failure produced no diagnostic: $SAVE_ERR"
fi

# --- clear: removes the scratch file (idempotent) ---------------------------

sti_draft_clear "$DRAFT"
if [ -f "$DRAFT" ]; then
  no "draft_clear: scratch file still present after clear"
else
  ok "draft_clear: removes the scratch file"
fi
if sti_draft_clear "$DRAFT"; then
  ok "draft_clear: idempotent (no error when already gone)"
else
  no "draft_clear: errored on an already-absent file"
fi

# --- find: resume detection matches only the same slug ----------------------

FDIR="$TMP/find-stride"
mkdir -p "$FDIR"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T100000 alpha)" "alpha draft body"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T110000 beta)"  "beta draft body"
: > "$(sti_draft_path "$FDIR" 2026-05-12T120000 gamma)"   # empty -> ignored

assert_eq "draft_find: returns the matching-slug draft only (two slugs in flight)" \
  "$(sti_draft_find "$FDIR" alpha)" \
  "$FDIR/2026-05-12T100000-alpha-draft.md"

sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T130000 oauth)" "oauth body"
NOAUTH="$(sti_draft_find "$FDIR" auth 2>/dev/null || true)"
if [ -z "$NOAUTH" ]; then
  ok "draft_find: slug 'auth' does not match 'oauth' (dash-delimited suffix)"
else
  no "draft_find: 'auth' cross-matched a different slug: $NOAUTH"
fi

NONE="$(sti_draft_find "$FDIR" does-not-exist 2>/dev/null || true)"
if [ -z "$NONE" ]; then
  ok "draft_find: no matching draft -> empty stdout + non-zero (fresh session)"
else
  no "draft_find: leaked output for a slug with no draft: $NONE"
fi

EMPTY_ONLY="$(sti_draft_find "$FDIR" gamma 2>/dev/null || true)"
if [ -z "$EMPTY_ONLY" ]; then
  ok "draft_find: an empty-only draft is not offered for resume (partial -> fresh)"
else
  no "draft_find: offered an empty draft for resume: $EMPTY_ONLY"
fi

sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T090000 multi)" "older"
sti_draft_save "$(sti_draft_path "$FDIR" 2026-05-12T140000 multi)" "newer"
assert_eq "draft_find: latest ISO timestamp wins for a repeated slug" \
  "$(sti_draft_find "$FDIR" multi)" \
  "$FDIR/2026-05-12T140000-multi-draft.md"

ABS="$(sti_draft_find "$TMP/no-such-dir" anything 2>/dev/null || true)"
if [ -z "$ABS" ]; then
  ok "draft_find: absent scratch dir -> empty stdout + non-zero (no crash)"
else
  no "draft_find: leaked output for an absent dir: $ABS"
fi

# --- find: anchored on the timestamp, so a suffix slug never matches ---------

ADIR="$TMP/anchor-stride"
mkdir -p "$ADIR"
sti_draft_save "$(sti_draft_path "$ADIR" 2026-05-12T120000 user-auth)" "user-auth body"
UA="$(sti_draft_find "$ADIR" auth 2>/dev/null || true)"
if [ -z "$UA" ]; then
  ok "draft_find: slug 'auth' does not match a 'user-auth' draft (timestamp-anchored)"
else
  no "draft_find: 'auth' matched another topic's draft: $UA"
fi
assert_eq "draft_find: slug 'user-auth' still finds its own draft" \
  "$(sti_draft_find "$ADIR" user-auth)" "$ADIR/2026-05-12T120000-user-auth-draft.md"
sti_draft_save "$(sti_draft_path "$ADIR" 2026-05-12T110000 auth)" "auth body"
assert_eq "draft_find: with both present, 'auth' returns the auth draft even though user-auth is newer" \
  "$(sti_draft_find "$ADIR" auth)" "$ADIR/2026-05-12T110000-auth-draft.md"
printf 'x' > "$ADIR/notes-auth-draft.md"
NOTS="$(sti_draft_find "$ADIR" auth)"
assert_eq "draft_find: a non-timestamp prefix is never matched" "$NOTS" "$ADIR/2026-05-12T110000-auth-draft.md"

# --- save: content from stdin, verbatim ---------------------------------------

SDIR="$TMP/stdin-stride"
SPATH="$(sti_draft_path "$SDIR" 2026-05-12T103000 stdin)"
# shellcheck disable=SC2016  # the literal $ and backticks are the point
printf '%s\n' 'Line one with "double" and '"'"'single'"'"' quotes' 'cost: $HOME $(id) `whoami` \n stays literal' '' 'last line' > "$TMP/stdin-expected"
sti_draft_save "$SPATH" < "$TMP/stdin-expected"
rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$TMP/stdin-expected" "$SPATH"; then
  ok "draft_save: reads multi-line stdin with quotes, \$ and backticks verbatim"
else
  no "draft_save: stdin content changed or save failed (rc=$rc)"
fi
sti_draft_save "$SPATH" "argument form" < /dev/null
assert_eq "draft_save: the argument form still works (and wins over stdin)" "$(cat "$SPATH")" "argument form"
EPATH="$(sti_draft_path "$SDIR" 2026-05-12T103000 emptyin)"
sti_draft_save "$EPATH" < /dev/null
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$EPATH" ] && [ ! -s "$EPATH" ]; then
  ok "draft_save: empty stdin writes an empty draft (exit 0), which find never offers"
else
  no "draft_save: empty stdin mishandled (rc=$rc)"
fi
EF="$(sti_draft_find "$SDIR" emptyin 2>/dev/null || true)"
assert_eq "draft_find: an empty stdin draft is not offered for resume" "$EF" ""

# --- save: the scratch dir ignores itself --------------------------------------

GDIR="$TMP/selfignore/.stride"
sti_draft_save "$(sti_draft_path "$GDIR" 2026-05-12T103000 gi)" "body"
assert_eq "draft_save: creating the scratch dir writes <dir>/.gitignore containing '*'" "$(cat "$GDIR/.gitignore")" "*"
printf 'custom\n' > "$GDIR/.gitignore"
sti_draft_save "$(sti_draft_path "$GDIR" 2026-05-12T103000 gi)" "body again"
assert_eq "draft_save: an existing .gitignore is never overwritten" "$(cat "$GDIR/.gitignore")" "custom"

PRE="$TMP/preexisting/.stride"
mkdir -p "$PRE"
printf 'keep-me\n' > "$PRE/.gitignore"
sti_draft_save "$(sti_draft_path "$PRE" 2026-05-12T103000 pre)" "body"
assert_eq "draft_save: a pre-existing .stride/.gitignore with other content is left alone" "$(cat "$PRE/.gitignore")" "keep-me"

PRE2="$TMP/preexisting2/.stride"
mkdir -p "$PRE2"
sti_draft_save "$(sti_draft_path "$PRE2" 2026-05-12T103000 pre)" "body"
assert_eq "draft_save: an existing .stride dir without a .gitignore gets one" "$(cat "$PRE2/.gitignore" 2>/dev/null)" "*"

PLAIN="$TMP/plain-dir"
mkdir -p "$PLAIN"
sti_draft_save "$PLAIN/2026-05-12T103000-plain-draft.md" "body"
if [ ! -e "$PLAIN/.gitignore" ]; then
  ok "draft_save: an existing directory not named .stride never gets a .gitignore"
else
  no "draft_save: wrote a .gitignore into an existing non-scratch directory"
fi

DDIR="$TMP/dir-helper/.stride"
if sti_draft_dir "$DDIR" && [ -d "$DDIR" ] && [ "$(cat "$DDIR/.gitignore")" = "*" ] && [ -z "$(ls "$DDIR" | grep -v '^$')" ]; then
  ok "draft_dir: creates the scratch dir and its self-ignore file, and no draft"
else
  no "draft_dir: did not create the scratch dir and .gitignore"
fi
if sti_draft_dir "" 2>/dev/null; then no "draft_dir: accepted an empty dir"; else ok "draft_dir: empty dir is a usage error"; fi

GREPO="$TMP/git-repo"
mkdir -p "$GREPO"
git -C "$GREPO" init -q
( cd "$GREPO" && sti_draft_save "$(sti_draft_path .stride 2026-05-12T103000 repo)" "secret-ish ideation prose" )
STATUS="$(git -C "$GREPO" status --porcelain --untracked-files=all)"
if [ -z "$STATUS" ]; then
  ok "draft_save: in a fresh repo, git status shows nothing under .stride/ after a save"
else
  no "draft_save: the draft shows up in git status" "$STATUS"
fi

# A pre-existing .stride/.gitignore that does not cover drafts is kept, and
# the drafts are still ignored (through the local .git/info/exclude).
CREPO="$TMP/cache-repo"
mkdir -p "$CREPO/.stride"
git -C "$CREPO" init -q
printf 'cache/\n' > "$CREPO/.stride/.gitignore"
( cd "$CREPO" && sti_draft_save "$(sti_draft_path .stride 2026-05-12T103000 cached)" "prose" )
if git -C "$CREPO" status --porcelain --untracked-files=all | grep -q 'draft\.md'; then
  no "draft_dir: a draft shows up in git status despite the existing .stride/.gitignore"
else
  ok "draft_dir: a .stride/.gitignore that does not cover drafts still leaves drafts ignored"
fi
assert_eq "draft_dir: the existing .stride/.gitignore is not modified" "$(cat "$CREPO/.stride/.gitignore")" "cache/"
if grep -qx '/.stride/\*-draft.md' "$CREPO/.git/info/exclude"; then
  ok "draft_dir: the fallback pattern lives in the local .git/info/exclude, not a tracked file"
else
  no "draft_dir: no draft pattern in .git/info/exclude"
fi

# A rule that re-includes drafts makes the helper refuse instead of writing.
NREPO="$TMP/negate-repo"
mkdir -p "$NREPO/.stride"
git -C "$NREPO" init -q
printf '!*-draft.md\n' > "$NREPO/.stride/.gitignore"
( cd "$NREPO" && sti_draft_save "$(sti_draft_path .stride 2026-05-12T103000 neg)" "prose" ) 2>"$TMP/neg.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q 'would not be ignored' "$TMP/neg.err" && [ ! -e "$NREPO/.stride/2026-05-12T103000-neg-draft.md" ]; then
  ok "draft_save: refuses (non-zero, no draft written) when a .gitignore rule re-includes drafts"
else
  no "draft_save: wrote or accepted a draft git would not ignore (rc=$rc)"
fi

if [ "$(id -u)" != "0" ]; then
  RO="$TMP/readonly"
  mkdir -p "$RO"
  chmod 555 "$RO"
  sti_draft_save "$RO/.stride/2026-05-12T103000-ro-draft.md" "body" 2>"$TMP/ro.err"
  rc=$?
  chmod 755 "$RO"
  if [ "$rc" -ne 0 ] && grep -q 'sti_draft_save: cannot' "$TMP/ro.err"; then
    ok "draft_save: a read-only parent fails non-zero with a sti_draft_save message"
  else
    no "draft_save: read-only parent did not fail cleanly (rc=$rc)"
  fi
else
  ok "draft_save: read-only parent check skipped (running as root)"
fi

# --- sourcing leaves the caller's shell options alone ----------------------
# A skill fragment sources this helper into its own shell; a file-scope
# `set -u` here would turn nounset on there, and an unset optional variable
# such as CONTINUE_PATH would then abort the step.
opts="$(bash -c '. "$1"; case $- in *u*) echo nounset-on;; *) echo nounset-off;; esac' _ "${SCRIPT_DIR}/draft.sh")"
assert_eq "sourcing draft.sh leaves nounset off in the caller" "$opts" "nounset-off"
out="$(bash -c '. "$1"; if [ -n "$CONTINUE_PATH" ]; then echo set; else echo unset; fi; sti_draft_path .stride 2026-05-12T103000 foo >/dev/null && echo ok' _ "${SCRIPT_DIR}/draft.sh" 2>&1)"
assert_eq "after sourcing draft.sh, an unset optional variable reads as empty" "$out" "unset
ok"

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
