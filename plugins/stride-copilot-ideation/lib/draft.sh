#!/usr/bin/env bash
# stride-ideation intra-session draft autosave helpers.
#
# Pure functions used by the stride-ideation-ideate skill to persist an
# in-progress ideation draft (answered sections + round state) to a gitignored
# scratch file under .stride/, so an interruption mid-session is recoverable and
# a later session can offer to resume it:
#
#   sti_draft_path  <dir> <ts> <slug>   -> <dir>/<ts>-<slug>-draft.md
#   sti_draft_find  <dir> <slug>        -> path of the latest NON-EMPTY draft
#                                          named <YYYY-MM-DDTHHMMSS>-<slug>-draft.md
#                                          (any timestamp), or non-zero if none
#   sti_draft_save  <path> [<content>]  -> writes <content> to <path>; with no
#                                          <content> argument it reads the
#                                          content from stdin (creating its
#                                          parent dir, which ignores itself)
#   sti_draft_dir   <dir>               -> creates the scratch dir (if needed)
#                                          and its self-ignore file
#   sti_draft_load  <path>              -> emits the draft content to stdout
#   sti_draft_exists <path>             -> exit 0 if the draft exists and is
#                                          non-empty, non-zero otherwise
#   sti_draft_clear <path>              -> removes the draft (no error if gone)
#
# A PowerShell mirror lives at lib/draft.ps1 (PascalCase-with-hyphen cmdlets).
#
# Filename rule: the scratch path pairs with the eventual requirements doc by
# reusing the <ts>-<slug>-<artifact> convention from sti_unique_path, with the
# artifact token `draft`. The draft lives under a GITIGNORED .stride/ path so
# half-finished, possibly sensitive ideation is never committed; the helper
# never serializes any secret — it only writes the content it is handed.
#
# Resume keys on the SLUG, not the session timestamp: a fresh session has a new
# timestamp, so sti_draft_find globs every <ts>-<slug>-draft.md under the
# scratch dir and returns the latest match (ISO timestamps sort lexically). The
# glob is anchored on the full timestamp prefix, so a different slug never
# matches — not `oauth` for `auth`, and not `user-auth` for `auth` either (a
# bare `*-auth-draft.md` suffix would have matched both).
#
# Self-ignoring scratch dir: when sti_draft_dir (which sti_draft_save calls)
# creates the scratch dir — or is handed one named `.stride` — it also writes
# <dir>/.gitignore containing
# `*` if that file is absent, so drafts stay out of `git add -A` in any
# project without touching the project's own .gitignore. An existing
# <dir>/.gitignore is never overwritten, and no other directory gets one.
#
# Inside a git work tree it then checks that a draft name in <dir> really is
# ignored. An existing <dir>/.gitignore may not cover drafts (say it only lists
# `cache/`); then it adds `/<dir>/*-draft.md` to the repository's local
# .git/info/exclude — never a tracked file — and checks again. If drafts are
# still not ignored (a `!` rule re-includes them), it fails rather than let a
# draft be swept into a commit.
#
# All non-error output is written to stdout. Errors go to stderr with a
# non-zero exit code. Source this file, or call functions directly via:
#   bash -c '. lib/draft.sh; sti_draft_path .stride 2026-05-12T103000 foo'

# No file-scope `set -u`: this file is sourced into the caller's shell, and a
# shell option set here would leak into it (an unset optional variable in a
# later skill fragment would then abort the step). Every function reads its
# arguments with ${N:-} defaults instead; the test scripts keep strict mode.

sti_draft_path() {
  local dir="${1:-}"
  local ts="${2:-}"
  local slug="${3:-}"
  if [ -z "$dir" ] || [ -z "$ts" ] || [ -z "$slug" ]; then
    echo "sti_draft_path: usage: sti_draft_path <dir> <ts> <slug>" >&2
    return 1
  fi
  printf '%s' "${dir%/}/${ts}-${slug}-draft.md"
}

sti_draft_find() {
  # Find the latest NON-EMPTY scratch draft for <slug> under <dir>, regardless
  # of session timestamp. Returns its path on stdout, or non-zero (no stdout)
  # when the directory is absent or no non-empty draft matches. Empty draft
  # files are ignored so a zero-length scratch never triggers a resume offer.
  local dir="${1:-}"
  local slug="${2:-}"
  if [ -z "$dir" ] || [ -z "$slug" ]; then
    echo "sti_draft_find: usage: sti_draft_find <dir> <slug>" >&2
    return 1
  fi
  [ -d "$dir" ] || return 1
  local latest=""
  local f
  # Anchored on the full YYYY-MM-DDTHHMMSS prefix, so slug `auth` matches
  # neither `oauth` nor `user-auth`. With no match (and nullglob unset), the
  # loop iterates once over the literal unexpanded pattern; the `[ -e "$f" ]`
  # guard skips it.
  local ts_glob='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]'
  for f in "${dir%/}/"$ts_glob"-${slug}-draft.md"; do
    [ -e "$f" ] || continue
    [ -s "$f" ] || continue
    # Bash expands globs in collation order, but compare explicitly so the
    # "latest ISO timestamp wins" contract does not depend on locale ordering.
    if [ -z "$latest" ] || [ "$f" \> "$latest" ]; then
      latest="$f"
    fi
  done
  if [ -z "$latest" ]; then
    return 1
  fi
  printf '%s' "$latest"
}

sti_draft_save() {
  # Persist the draft to <path>, creating the parent directory if needed.
  # Content comes from the second argument when one is given (back-compat), or
  # else from stdin, written verbatim — so prose with quotes, `$` or backticks
  # never has to be shell-quoted. Side effects: that one file, the mkdir -p of
  # its dir, and the dir's self-ignore file (see the header).
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (no <content>: read stdin)" >&2
    return 1
  fi
  if [ "$#" -lt 2 ] && [ -t 0 ]; then
    echo "sti_draft_save: usage: sti_draft_save <path> [<content>]  (no <content>: read stdin)" >&2
    return 1
  fi
  local dir
  dir="$(dirname "$path")"
  # sti_draft_dir's own stderr says why (no dir, or drafts not ignored).
  if ! sti_draft_dir "$dir"; then
    echo "sti_draft_save: cannot create scratch directory: $dir" >&2
    return 1
  fi
  if [ "$#" -ge 2 ]; then
    if ! printf '%s' "$2" > "$path" 2>/dev/null; then
      echo "sti_draft_save: cannot write scratch draft: $path" >&2
      return 1
    fi
  elif ! cat > "$path" 2>/dev/null; then
    echo "sti_draft_save: cannot write scratch draft: $path" >&2
    return 1
  fi
}

sti_draft_dir() {
  # Create the scratch dir <dir> if needed and make it ignore itself: write
  # <dir>/.gitignore containing `*` when that file is absent AND either this
  # call created <dir> or <dir> is named `.stride`. An existing .gitignore is
  # never overwritten, and an existing directory with any other name (the
  # project root, say) never gets one. The skill calls this before its first
  # autosave, because it writes the draft itself with the file-write tool.
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    echo "sti_draft_dir: usage: sti_draft_dir <dir>" >&2
    return 1
  fi
  local created=0
  [ -d "$dir" ] || created=1
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "sti_draft_dir: cannot create scratch directory: $dir" >&2
    return 1
  fi
  if [ ! -e "$dir/.gitignore" ] && { [ "$created" -eq 1 ] || [ "$(basename "$dir")" = ".stride" ]; }; then
    if ! printf '*\n' > "$dir/.gitignore" 2>/dev/null; then
      echo "sti_draft_dir: cannot write $dir/.gitignore" >&2
      return 1
    fi
  fi
  _sti_draft_dir_ensure_ignored "$dir"
}

_sti_draft_dir_ensure_ignored() {
  # Outside a git work tree there is nothing to sweep drafts into: done.
  local dir="$1" probe="0000-00-00T000000-probe-draft.md" exclude prefix
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$dir" check-ignore -q -- "$probe" 2>/dev/null && return 0
  exclude="$(git -C "$dir" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)" ||
    exclude="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)/info/exclude"
  prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)"
  if mkdir -p "$(dirname "$exclude")" 2>/dev/null &&
     printf '/%s*-draft.md\n' "$prefix" >> "$exclude" 2>/dev/null &&
     git -C "$dir" check-ignore -q -- "$probe" 2>/dev/null; then
    return 0
  fi
  echo "sti_draft_dir: drafts in $dir would not be ignored by git (a .gitignore rule there re-includes them); refusing so a draft cannot be committed" >&2
  return 1
}

sti_draft_load() {
  # Emit the draft content at <path> to stdout. Errors if the file is absent.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_load: usage: sti_draft_load <path>" >&2
    return 1
  fi
  if [ ! -f "$path" ]; then
    echo "sti_draft_load: no scratch draft at: $path" >&2
    return 1
  fi
  cat "$path"
}

sti_draft_exists() {
  # Predicate: exit 0 if <path> is an existing NON-EMPTY draft, else non-zero.
  # No stdout. A zero-length scratch is treated as "no resumable draft".
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_exists: usage: sti_draft_exists <path>" >&2
    return 1
  fi
  [ -s "$path" ]
}

sti_draft_clear() {
  # Remove the scratch draft at <path>. Idempotent: no error if already gone.
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "sti_draft_clear: usage: sti_draft_clear <path>" >&2
    return 1
  fi
  rm -f "$path"
}
