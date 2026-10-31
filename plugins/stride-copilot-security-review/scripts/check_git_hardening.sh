#!/usr/bin/env bash
# Offline integration check for the git hardening (upstream D377, W2573).
#
# check_agent_contract.sh pins the text of the five git forms, the probe's
# guard line and its copy step. This script runs that text against a real git:
# it builds a scratch repository whose own config names a marker program for
# core.fsmonitor, diff.external, a diff driver command, a textconv driver and
# gpg.program (with log.showSignature and a signed commit), then runs each of
# the five forms exactly as the README lists them, and the guard and the copy
# step exactly as the probe block has them (in the reproduction mode file
# the skill sends the agent, since W2285), and fails if any marker
# program ran. Unflagged controls must make every marker program run, so a
# scratch repository that could not have caught a configured program fails the
# check instead of passing it.
#
# Not covered: core.pager (no terminal is attached, so git never pages), a
# submodule's diff programs, and the lazy fetch of a partial clone (it would
# need a promisor remote). The forms carry --no-pager, --submodule=short and
# --no-lazy-fetch for those, pinned as text by check_agent_contract.sh.
#
# Needs git 2.44 or later (--no-lazy-fetch); with an older git it prints a
# skip line and exits 0, as the agent itself would run nothing there. Offline:
# no network, no Copilot CLI, no token. Writes only under a mktemp -d
# directory, removed on exit, with HOME and the global and system git config
# pointed away from the caller's. It runs only text from this plugin's own
# README and reproduction mode file, which check_agent_contract.sh pins byte
# for byte.
#
# Usage:
#   bash scripts/check_git_hardening.sh [probe-file (default: the reproduction mode file)] [readme-file]
#
# Exit code: 0 when no marker ran and every control fired (or git is too
# old); 1 otherwise. Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$SCRIPT_DIR/.."
# W2285: the probe block lives in the reproduction mode file the skill sends.
AGENT="${1:-$ROOT/skills/security-review-essentials/modes/reproduction.md}"
README="${2:-$ROOT/README.md}"
fail=0

for f in "$AGENT" "$README"; do
  [ -f "$f" ] && [ -r "$f" ] || { echo "FAIL: file not found or not readable: $f"; exit 1; }
done

gv="$(git --version 2>/dev/null)" || { echo "FAIL: git is not installed"; exit 1; }
gv="${gv#git version }"
IFS=. read -r gmaj gmin _ <<EOF
$gv
EOF
case "$gmaj:$gmin" in
  ( *[!0-9:]* | :* | *: ) echo "FAIL: cannot read the git version: $gv"; exit 1 ;;
esac
if [ "$gmaj" -lt 2 ] || { [ "$gmaj" -eq 2 ] && [ "$gmin" -lt 44 ]; }; then
  echo "skip: git $gv is older than 2.44, which rejects --no-lazy-fetch; the agent runs nothing there"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-git-hardening.XXXXXX")" || { echo "FAIL: no temporary directory"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The five forms, as the README lists them, and the probe's two git lines, as
# the agent's probe block has them.
forms="$(grep -F 'and five git forms' "$README" | grep -oE '`git --no-pager[^`]*`' | tr -d '`')"
nforms="$(printf '%s\n' "$forms" | grep -c .)"
if [ "$nforms" -ne 5 ]; then
  echo "FAIL: the README lists five git forms -- found $nforms"; fail=1
fi
probe="$(awk '/^- \*\*Reproduce only in a temporary copy/ { f = 1; next }
  f && !b && /^  ```bash$/ { b = 1; next } b && /^  ```$/ { exit } b' "$AGENT")"
guard="$(printf '%s\n' "$probe" | grep -E '^    git .* version ' | sed 's/^    //')"
copy="$(printf '%s\n' "$probe" | grep -E '^    git .*ls-files .*tar ' | sed 's/^    //')"
[ -n "$guard" ] || { echo "FAIL: the probe block has a git version guard line"; fail=1; }
[ -n "$copy" ] || { echo "FAIL: the probe block has a git ls-files copy step"; fail=1; }

# The scratch repository and its marker programs. HOME and the global and
# system config are moved away, so only the repository's own config applies.
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
M="$TMP/markers"; mkdir "$M"
for k in fsmonitor external diffcmd textconv gpg; do
  printf '#!/bin/sh\necho ran >> "%s/%s"\nexit 0\n' "$M" "$k" > "$TMP/$k.sh"
  chmod +x "$TMP/$k.sh"
done
R="$TMP/repo"; mkdir "$R"
(
  cd "$R" || exit 1
  git init -q &&
  git config user.email check@example.invalid && git config user.name check &&
  git config commit.gpgsign false &&
  printf 'a\n' > f.txt && printf 'b\n' > g.y &&
  printf '*.txt diff=x\n*.y diff=z\n' > .gitattributes &&
  git add -A && git commit -q -m one &&
  printf 'a2\n' > f.txt && printf 'b2\n' > g.y && git add -A &&
  tree="$(git write-tree)" && parent="$(git rev-parse HEAD)" &&
  # A second commit carrying a signature header, so log.showSignature would
  # call gpg.program on it.
  obj="$(printf 'tree %s\nparent %s\nauthor check <c> 1700000000 +0000\ncommitter check <c> 1700000000 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n iQEzBAABCAAdFiEE\n -----END PGP SIGNATURE-----\n\ntwo\n' "$tree" "$parent" | git hash-object -t commit -w --stdin)" &&
  git update-ref HEAD "$obj" &&
  printf 'a3\n' > f.txt && git add f.txt &&
  git config core.fsmonitor "$TMP/fsmonitor.sh" &&
  git config diff.external "$TMP/external.sh" &&
  git config diff.z.command "$TMP/diffcmd.sh" &&
  git config diff.x.textconv "$TMP/textconv.sh" &&
  git config gpg.program "$TMP/gpg.sh" &&
  git config log.showSignature true
) || { echo "FAIL: could not build the scratch repository"; exit 1; }
C1="$(git -C "$R" rev-parse HEAD~1)"; C2="$(git -C "$R" rev-parse HEAD)"

markers() { ls "$M" | tr '\n' ' ' | sed 's/ $//'; }
# No glob: the form loop below runs with globbing off.
reset_markers() { rm -rf "$M" && mkdir "$M"; }

# run_quiet <label> <command...> -- the command must exit 0 and run no marker
run_quiet() {
  local label="$1" rc got; shift
  reset_markers
  ( cd "$R" && "$@" ) </dev/null >/dev/null 2>&1; rc=$?
  got="$(markers)"
  if [ "$rc" -ne 0 ]; then
    echo "FAIL: $label -- exit $rc"; fail=1
  elif [ -n "$got" ]; then
    echo "FAIL: $label -- ran a repository-configured program: $got"; fail=1
  else
    echo "ok: $label"
  fi
}

# run_control <label> <want-markers> <command...> -- every named marker must run
run_control() {
  local label="$1" want="$2" k miss=""; shift 2
  reset_markers
  ( cd "$R" && "$@" ) </dev/null >/dev/null 2>&1
  for k in $want; do [ -e "$M/$k" ] || miss="$miss $k"; done
  if [ -n "$miss" ]; then
    echo "FAIL: control: $label -- did not run:$miss, so the check could not see it"; fail=1
  else
    echo "ok: control: $label"
  fi
}

# The controls first: without them a quiet form proves nothing.
run_control "an unflagged commit-to-commit diff runs diff.external and the diff driver" "external diffcmd" git diff "$C1" "$C2"
run_control "an unflagged log -p runs textconv and gpg.program" "textconv gpg" git -c diff.external= log -p -2
run_control "an unflagged ls-files -m runs core.fsmonitor" "fsmonitor" git ls-files -m
run_control "the pre-D377 copy step runs core.fsmonitor" "fsmonitor" \
  sh -c 'git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C "$1"' sh "$(mktemp -d "$TMP/copy.XXXXXX")"

# The five README forms. Each is split into words with globbing off; the
# placeholder <commit> <commit> becomes two real commits, and log gets -p so
# it prints a patch, the shape a reviewer would run.
set -f
while IFS= read -r form; do
  [ -n "$form" ] || continue
  set -- $form
  args=()
  for w in "$@"; do
    case "$w" in
      ( '<commit>' ) if [ "${#args[@]}" -gt 0 ] && [ "${args[${#args[@]}-1]}" = "$C1" ]; then args+=("$C2"); else args+=("$C1"); fi ;;
      ( * ) args+=("$w") ;;
    esac
  done
  case " $form " in ( *' log '* ) args+=("-p" "-2") ;; esac
  run_quiet "the README form runs no repository-configured program: $(printf '%s' "$form" | sed 's/.*gpg.x509.program=false //')" "${args[@]}"
done <<EOF
$forms
EOF
set +f

# The probe's guard line and copy step, as the agent has them.
if [ -n "$guard" ]; then
  run_quiet "the probe's guard line passes and runs no repository-configured program" sh -c "$guard"
fi
if [ -n "$copy" ]; then
  D="$(mktemp -d "$TMP/copy.XXXXXX")"
  run_quiet "the probe's copy step runs no repository-configured program" env d="$D" sh -c "$copy"
  if [ -f "$D/f.txt" ] && [ -f "$D/.gitattributes" ]; then
    echo "ok: the probe's copy step copies the files"
  else
    echo "FAIL: the probe's copy step copies the files -- the copy is missing files"; fail=1
  fi
fi

# Self-tests: a README form with --no-textconv dropped, the pre-D377 copy step
# and a missing guard line must each make this script fail.
if [ -z "${CHECK_GIT_HARDENING_CHILD:-}" ]; then
  B="$TMP/broken"; mkdir "$B"
  expect_fail() { # $1=label $2=needle $3=agent $4=readme
    local out rc
    out="$(CHECK_GIT_HARDENING_CHILD=1 bash "$SELF" "$3" "$4" </dev/null 2>&1)"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF -- "$2"; then
      echo "ok: self-test: $1"
    else
      echo "FAIL: self-test: $1 -- exit $rc, or output lacks: $2"; fail=1
    fi
  }
  # bre <file> <from> <to> <out> -- fixed-string replace, refusing a no-op
  bre() {
    FROM="$2" TO="$3" awk 'BEGIN { from = ENVIRON["FROM"]; to = ENVIRON["TO"] }
      { l = $0; o = ""
        while ((i = index(l, from)) > 0) { o = o substr(l, 1, i - 1) to; l = substr(l, i + length(from)) }
        print o l }' "$1" > "$4"
    ! cmp -s "$1" "$4" || { echo "FAIL: self-test: the break did not land: $2"; fail=1; }
  }
  bre "$README" 'diff --cached --no-ext-diff --no-textconv --submodule=short`' 'diff --cached --no-ext-diff --submodule=short`' "$B/README.md"
  expect_fail "a README diff --cached form without --no-textconv fails" \
    "ran a repository-configured program: textconv" "$AGENT" "$B/README.md"
  bre "$AGENT" 'git --no-lazy-fetch -c core.fsmonitor=false ls-files -z' 'git ls-files -z' "$B/plain-copy.agent.md"
  expect_fail "the pre-D377 copy step fails" \
    "FAIL: the probe's copy step runs no repository-configured program -- ran a repository-configured program: fsmonitor" "$B/plain-copy.agent.md" "$README"
  grep -vF 'git --no-lazy-fetch version' "$AGENT" > "$B/no-guard.agent.md"
  expect_fail "a probe block without the guard line fails" \
    "FAIL: the probe block has a git version guard line" "$B/no-guard.agent.md" "$README"
fi

if [ "$fail" -ne 0 ]; then
  echo "git hardening: FAILED"
  exit 1
fi
echo "git hardening: no repository-configured program ran"
