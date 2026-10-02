---
name: stride-ideation-ideate
description: Drive an interactive ideation session that turns a fuzzy idea into a committed requirements markdown document. Activate when the user wants to ideate, brainstorm, scope a new feature, write a requirements doc, design brief, or pre-decomposition scoping doc. Supports --continue <path> (or --continue=<path>) to refine a prior requirements doc, --input <path> to seed draft sections from a brain-dump file, and --profile <lean|product|discovery|lean-startup> to select the round structure and reviewer rubric (default lean: the shared core with no profile augmentations). Hard-gated by the stride-ideation skill on the seven required sections; terminal state is the written doc (does NOT auto-activate the stride-ideation-stridify skill). Copilot port of the upstream /stride-ideation:ideate command.
skills_version: 1.0
---

# stride-ideation-ideate

Drive an interactive ideation session that produces a committed `*-requirements.md` document under `docs/ideation/`. The protocol — round-based question batching, hard-gated sections, advisory reviewer pass — is defined in `skills/stride-ideation/SKILL.md`. This skill is the surface: it parses arguments (or prompts the user for them), captures the session timestamp, resolves the slug, drives the protocol skill, and finishes by writing and committing the doc.

## Activation

Activate this skill when the user:

- Describes a new feature, capability, or initiative in fuzzy terms ("we should probably do X", "what if we…")
- Explicitly asks for a requirements doc, scoping doc, or design brief
- Has a piece of work too broad to decompose into Stride tasks without first capturing the shape
- Is choosing between approaches and needs to articulate goals + constraints before picking one

If the user activates the skill with arguments embedded in the message (e.g., "ideate notifications system" or "ideate --profile=product approval flows" or "ideate --continue docs/ideation/<existing>-requirements.md"), parse those per Step 1. Otherwise prompt for the topic via the platform's question UI.

## Running the shell blocks

Every fenced `bash` block in this skill is **self-contained**. Run each one as a single shell call, and assume nothing from an earlier call has survived — no variable, no sourced function, no `cd`. Whether the host reuses one shell session between calls is not something this skill relies on either way. Concretely:

- **Earlier values arrive as literals.** A block that needs a value an earlier step produced opens with a `# Carried forward:` line naming it, then assigns it, e.g. `SLUG='<value of SLUG>'`. Replace the `<value of …>` text with the value you recorded, **inside the single quotes**, writing any `'` within the value as `'\''` — so a value holding spaces or shell characters can neither split nor execute. Each step says which values it produces for you to record.
- **Each block sources the helper it calls.** A block that calls an `sti_` function sources `lib/filename.sh` or `lib/draft.sh` itself, from the plugin root (next section), after checking the file is there.
- **Failure is a non-zero status, never the end of your shell.** Each block's body runs inside `( … )`, so an `exit 1` ends only that subshell and the call returns a non-zero status. When a block returns non-zero, relay its `stride-ideation:` stderr verbatim and stop the skill — do not run the next step.
- **Optional values carry a default.** A value that may legitimately be absent (`CONTINUE_PATH`, `DRAFT_PATH`) is read as `${NAME:-}`, so an unset one reads as empty rather than aborting the block.

**On a Windows host without bash**, use the PowerShell helpers each step names instead: dot-source `lib/filename.ps1` or `lib/draft.ps1` from the plugin root and call the `Sti-` cmdlet with the same arguments (`sti_slugify` → `Sti-Slugify`, `sti_unique_path` → `Sti-UniquePath`, `sti_draft_find` → `Sti-DraftFind`, and so on — the header table of each `.ps1` file maps every name). The same rules apply: carried-forward values as single-quoted literals (a `'` inside one is written `''`), and a failed cmdlet stops the skill.

## Resolving the plugin root

The plugin root is the directory **two levels above this SKILL.md**: the file you loaded is `<plugin root>/skills/stride-ideation-ideate/SKILL.md`, so strip the last two path components from its absolute path. Record it once as `PLUGIN_ROOT`, and verify it with this block before Step 1:

```bash
(
# Carried forward: PLUGIN_ROOT
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
[ -f "$PLUGIN_ROOT/lib/filename.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/filename.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
echo "stride-ideation: plugin root OK: $PLUGIN_ROOT"
)
```

On a PowerShell-only host, verify it the same way before dot-sourcing anything:

```powershell
$PluginRoot = '<value of PLUGIN_ROOT>'
if (-not (Test-Path -LiteralPath (Join-Path $PluginRoot 'lib/filename.ps1'))) { throw "stride-ideation: cannot find the plugin helpers: $PluginRoot/lib/filename.ps1 does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." }
```

`throw` reports the failure without closing the PowerShell session; relay its message and stop.

Carry `PLUGIN_ROOT` into every block that sources a helper; each such block repeats the same check before sourcing anything.

If that check fails, relay the message and stop — never guess another location, and never source a helper from the current directory instead.

## What to do

Follow these steps in order. Do NOT skip steps.

### Step 1: Parse arguments

The user may pass arguments inline in the activation request (e.g., "ideate --profile=product approval flows", or "ideate --continue docs/ideation/2026-05-12T120000-foo-requirements.md"). If no arguments are present, prompt the user for the topic via the platform's question UI.

Parse arguments in this fixed order — `--continue` first, then `--input`, then `--profile`, then everything remaining is `TOPIC`:

- If `--continue` appears, set `CONTINUE_PATH` to the value of the **next** token and remove both tokens — or, for the `--continue=<path>` form, to the post-`=` portion (split on the FIRST `=` only, so a path containing `=` is kept whole) and remove the single token. Accept both shapes. If `--continue` has no value — a bare trailing `--continue`, `--continue=`, or `--continue` followed by another flag (any token starting with `--`) — print `stride-ideation: --continue requires a path to a prior -requirements.md doc` and stop **before any session work begins**; never fall through to a fresh session. In `--continue` mode the topic is inherited from the source file and not re-prompted.
- If `--input` appears (accept both `--input <path>` and `--input=<path>` shapes, matching how `--continue` accepts both forms), set `INPUT_PATH` to the parsed value and remove the consumed tokens. `--input` is a **freeform brain-dump seed** — a Slack thread, scratch notes, meeting notes — that pre-populates draft sections; it is **distinct from `--continue`**, which refines an already-committed `-requirements.md` document. The two are independent and composable: if **both** are passed, `--continue` supplies the starting document and `--input` supplies additional raw seed content; neither overrides the other, nothing is silently dropped, and the slug still follows the `--continue` rule below (see Step 3). `--input` never changes the topic or the slug — it only seeds content.
- If `--profile` appears (accept both `--profile <name>` and `--profile=<name>` shapes, matching how `--continue` accepts both forms), set `PROFILE` to the parsed value and remove the consumed tokens. The accepted values are exactly `lean`, `product`, `discovery`, `lean-startup`. If the value is missing or is not one of these four, print a one-line error naming the offending value and the accepted set (e.g., `stride-ideation: unknown --profile value 'foo'; expected one of: lean, product, discovery, lean-startup`) and stop **before any session work begins** — do NOT prompt, do NOT default to lean on a typo, and do NOT fall through to the topic parser.
- If `--profile` is absent, **recommend a profile before the rounds begin** rather than silently defaulting. Ask the user once via the Copilot CLI platform's question UI (the same prompt primitive the skill uses elsewhere — NOT Claude Code's `AskUserQuestion`), inferring a suggested profile from the topic (in `--continue` mode, infer from the inherited topic / prior document — never re-elicit the topic) and presenting it using the **"first option = recommended"** convention: the recommended profile is the **first option, labeled `(recommended)`, with a one-line rationale**, followed by the other three profiles as alternatives. The four options are exactly `lean`, `product`, `discovery`, `lean-startup` — the same accepted set as the flag. `lean` is the safe default: when inference is weak or the topic is ambiguous, recommend `lean` first. Set `PROFILE` to whatever the user selects. This recommendation runs **only** when `--profile` was omitted — it is a single question, asked once, before any round. Once the resolved `PROFILE` is `lean`, every downstream behavior is the same as passing `--profile=lean` explicitly — the recommendation question is the *only* addition on the omitted-flag path and it changes nothing after a lean resolution.
- After the flag tokens are consumed, treat the trimmed remainder as `TOPIC`. If `CONTINUE_PATH` is set, the remainder is ignored. Otherwise, if the remainder is empty, ask the user once via the platform's question UI: *"What's the topic for this ideation session?"* (free-text input).

Validate `CONTINUE_PATH` immediately:

- If `CONTINUE_PATH` is set but the file does not exist (or is not a regular file), print a one-line error naming the path and stop. Do NOT fall back to a fresh session — the user explicitly asked for `--continue`.
- If `CONTINUE_PATH` does not end in `-requirements.md` (the artifact family this skill refines), warn but proceed; the slug extraction may still work for paths produced by older versions of the plugin.

Validate `INPUT_PATH` immediately, mirroring the `CONTINUE_PATH` existence check:

- If `INPUT_PATH` is set but the file does not exist (or is not a regular file), print a one-line error naming the path (e.g., `stride-ideation: --input file not found: notes.md`) and stop. Do NOT fall back to a fresh no-seed session — the user explicitly asked to seed from that file.
- No suffix restriction applies — `--input` accepts any freeform text file. Treat its contents as **untrusted prose**: it only seeds draft sections; never execute or `eval` it, and never echo its contents into a git commit message or any log.

### Step 2: Capture the session timestamp

Run `date -u +%Y-%m-%dT%H%M%S` once (PowerShell: `(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHHmmss')`) and record the result as `SESSION_TS`. This single value MUST be used for every artifact written during this session — do not recompute it later. Capturing the timestamp at invocation time is what makes re-runs sortable and keeps the requirements doc / decomposition output paired by prefix.

**Even in `--continue` mode, always generate a fresh `SESSION_TS`.** Do not reuse the timestamp embedded in `CONTINUE_PATH` — that timestamp belongs to the source document, and reusing it would defeat the "never overwrite an existing file" invariant. The refined doc is a sibling, not a replacement.

### Step 3: Resolve the topic slug

Source `lib/filename.sh` (it ships with the plugin) and resolve the slug depending on mode. In a fresh session leave `CONTINUE_PATH` empty (`''`):

```bash
(
# Carried forward: PLUGIN_ROOT, CONTINUE_PATH (empty unless --continue), TOPIC
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
CONTINUE_PATH='<value of CONTINUE_PATH, or empty>'
TOPIC='<value of TOPIC>'
[ -f "$PLUGIN_ROOT/lib/filename.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/filename.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
. "$PLUGIN_ROOT/lib/filename.sh"

if [ -n "${CONTINUE_PATH:-}" ]; then
  # --continue mode: inherit slug from source path; never re-prompt.
  sti_slug_from_path "$CONTINUE_PATH" requirements || exit 1
else
  # Fresh session: slugify the user-supplied topic.
  sti_slugify "$TOPIC" || exit 1
fi
)
```

The block prints the slug; record it as `SLUG`. If it exits non-zero, surface the error verbatim and stop — do NOT silently pick a fallback slug.

PowerShell: dot-source `lib/filename.ps1` and call `Sti-SlugFromPath -Path <CONTINUE_PATH> -Artifact requirements` (`--continue` mode) or `Sti-Slugify -InputText <TOPIC>` (fresh session).

**Confirm `SLUG` with the user only in fresh-session mode.** In `--continue` mode the slug is inherited and locked — re-prompting would violate the "no re-prompt" acceptance criterion and risk accidentally diverging the artifact family. In fresh-session mode, ask the user via the platform's question UI offering the computed value as the first option and "Type a different slug" as a fallback. Either way, the slug is locked for the rest of the session.

### Step 4: Compute the target path (don't write yet)

Call `sti_unique_path docs/ideation "$SESSION_TS" "$SLUG" requirements md`, and in the same block check the `--continue` invariant described below:

```bash
(
# Carried forward: PLUGIN_ROOT, SESSION_TS, SLUG, CONTINUE_PATH (empty unless --continue)
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
SESSION_TS='<value of SESSION_TS>'
SLUG='<value of SLUG>'
CONTINUE_PATH='<value of CONTINUE_PATH, or empty>'
[ -f "$PLUGIN_ROOT/lib/filename.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/filename.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
. "$PLUGIN_ROOT/lib/filename.sh"

TARGET_PATH="$(sti_unique_path docs/ideation "$SESSION_TS" "$SLUG" requirements md)" || exit 1
if [ -n "${CONTINUE_PATH:-}" ] && [ "$TARGET_PATH" = "$CONTINUE_PATH" ]; then
  echo "stride-ideation: refusing to overwrite source document at $CONTINUE_PATH" >&2
  exit 1
fi
printf '%s\n' "$TARGET_PATH"
)
```

PowerShell: `Sti-UniquePath docs/ideation <SESSION_TS> <SLUG> requirements md` from `lib/filename.ps1`, then the same comparison against `CONTINUE_PATH`.

Record the printed path as `TARGET_PATH` — the path you WILL write to in Step 8. Do NOT create or touch this file yet. Pre-creating it as empty would leave a half-baked artifact on the filesystem if the user interrupts mid-session, which is the explicit failure mode the spec is guarding against.

**HARD INVARIANT — `--continue` mode:** `TARGET_PATH` MUST NOT equal `CONTINUE_PATH`. `sti_unique_path` builds the new path from a fresh `SESSION_TS`, so the two paths only collide if the user manually crafted a colliding name on disk in the same second — which the collision discriminator handles. The block above verifies the invariant before you continue: a `refusing to overwrite` failure stops the skill.

### Step 4b: Read the prior document (only in `--continue` mode)

If `CONTINUE_PATH` is set, **read-only** load its content via the platform's file-read tool. The skill will receive this content as starting context for the session. The source file is **never** edited, written, moved, or `git add`-ed during this skill — read access only. If you find yourself reaching for the file-edit or file-write tool against `CONTINUE_PATH`, stop: that is the failure mode the pitfall forbids.

In fresh-session mode, leave the prior-doc context empty.

### Step 4c: Read the input brain-dump (only when `--input` is set)

If `INPUT_PATH` is set, **read-only** load its content via the platform's file-read tool into `INPUT_NOTES`. The protocol skill receives this content as raw seed material that pre-populates draft sections wherever the notes clearly map to a gated section. The `--input` file carries the **same read-only invariant as the `--continue` source**: it is **never** edited, written, moved, or `git add`-ed during this skill — read access only. Its contents are untrusted prose: never execute or `eval` them, and never copy them into a commit message or log. If `INPUT_PATH` is not set, leave `INPUT_NOTES` empty.

`--input` and `--continue` are independent: both `PRIOR_DOC` and `INPUT_NOTES` may be non-empty in the same session (a prior committed doc *and* a fresh notes file), one may be set without the other, or neither. The seed lowers the starting cost — it does NOT lower the bar: the hard gates, the round-3 framing checkpoint, the premortem, and the reviewer pass all still run, and gaps or weak sections are still asked in the rounds.

### Step 4d: Detect an unfinished draft and resolve the autosave path

The requirements doc is not written until the hard gate passes (Step 8), so an interruption mid-session would otherwise lose every answer. To make a session recoverable, the protocol skill autosaves the in-progress draft after every round to a scratch file under `.stride/` (see Step 5 and the **Autosave** section of `skills/stride-ideation/SKILL.md`), and on start this step offers to resume any unfinished draft for the **same slug**. The block below also creates `.stride/` and makes it ignore itself — it writes `.stride/.gitignore` containing `*` when that file is absent, and never overwrites an existing one — so the draft cannot be swept into a commit even in a project whose own `.gitignore` says nothing about `.stride/`. If `.stride/` already has a `.gitignore` that does not cover drafts, the helper adds a draft pattern to the repository's local `.git/info/exclude` instead (never a tracked file); if a rule there re-includes drafts, it refuses, and this step turns autosave off for the session rather than write a draft git would pick up. The project's `.gitignore` is never touched.

Source the draft helper, prepare the scratch directory, and look for an existing draft keyed by `SLUG` (resume keys on the slug, not `SESSION_TS`, because a fresh run has a new timestamp). Use `lib/draft.sh` on Unix shells, or its mirror `lib/draft.ps1` (`Sti-DraftDir`, `Sti-DraftFind`) on Windows:

```bash
(
# Carried forward: PLUGIN_ROOT, SESSION_TS, SLUG
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
SESSION_TS='<value of SESSION_TS>'
SLUG='<value of SLUG>'
[ -f "$PLUGIN_ROOT/lib/draft.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/draft.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
. "$PLUGIN_ROOT/lib/draft.sh"

# Create .stride/ (if needed) with its self-ignore file before any autosave.
# If drafts there would not be ignored by git, autosave is off this session.
if sti_draft_dir .stride; then
  printf 'autosave=on\n'
else
  echo "stride-ideation: autosave is off for this session (drafts in .stride/ would not be ignored by git)" >&2
  printf 'autosave=off\n'
fi
EXISTING_DRAFT="$(sti_draft_find .stride "$SLUG" 2>/dev/null || true)"
printf 'existing_draft=%s\n' "$EXISTING_DRAFT"
printf 'fresh_draft=%s\n' "$(sti_draft_path .stride "$SESSION_TS" "$SLUG")"
)
```

`sti_draft_find` returns the latest **non-empty** scratch draft named `<YYYY-MM-DDTHHMMSS>-$SLUG-draft.md` under `.stride/` — anchored on the full timestamp, so a draft for `user-auth` is never offered when the slug is `auth` — or nothing when none exists (an empty or absent scratch yields no offer — a partial/corrupt draft safely falls back to a fresh session); the block prints it as `existing_draft=` and the fresh per-session path as `fresh_draft=`. **If it printed `autosave=off`, record `DRAFT_PATH` as empty and skip the rest of this step** — the protocol skill then saves nothing, and an interruption loses the session's answers rather than leaking them into a commit. Otherwise resolve `DRAFT_PATH` for this session:

- **If `existing_draft` is non-empty**, ask the user via the platform's question UI (NOT Claude Code's `AskUserQuestion`) whether to **resume** that draft or **start fresh** (offer "Resume" as the first option). On resume, record `DRAFT_PATH` as the `existing_draft` value so the session continues autosaving to — and the protocol skill loads from — that same file. On start-fresh, discard the abandoned draft with this block, then record `DRAFT_PATH` as the `fresh_draft` value:

  ```bash
  (
  # Carried forward: PLUGIN_ROOT, the existing_draft value
  PLUGIN_ROOT='<value of PLUGIN_ROOT>'
  EXISTING_DRAFT='<value of existing_draft>'
  [ -f "$PLUGIN_ROOT/lib/draft.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/draft.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
  . "$PLUGIN_ROOT/lib/draft.sh"
  sti_draft_clear "$EXISTING_DRAFT"
  )
  ```
- **If `existing_draft` is empty** (none found), record `DRAFT_PATH` as the `fresh_draft` value — a fresh per-session scratch path.

PowerShell: dot-source `lib/draft.ps1` and use `Sti-DraftDir .stride` (a non-zero `$LASTEXITCODE` means autosave is off, as above), `Sti-DraftFind .stride <SLUG>`, `Sti-DraftPath .stride <SESSION_TS> <SLUG>` and `Sti-DraftClear <path>`.

Only same-slug drafts are ever offered; a draft for a different in-flight topic is never surfaced here. The `.stride/` scratch directory ignores itself through its own `.gitignore` (written by the block above), and the scratch file is **never** `git add`-ed or committed, and **never** holds the Stride API token or any other secret — it carries only the in-progress draft prose.

### Step 5: Drive the `stride-ideation` protocol skill

Activate the `stride-ideation` skill (the protocol skill ported to `skills/stride-ideation/SKILL.md`) passing the topic, locked slug, session timestamp, target path, the prior document (if any), and the resolved profile. The protocol skill's contract specifies these inputs explicitly:

```
topic=<TOPIC>
slug=<SLUG>
session_ts=<SESSION_TS>
target_path=<TARGET_PATH>
prior_doc=<PRIOR_DOC>
input_notes=<INPUT_NOTES>
draft_path=<DRAFT_PATH>
profile=<PROFILE>
```

When `PRIOR_DOC` is non-empty, the protocol skill starts the session with that content already loaded as context — refining and sharpening rather than re-eliciting every section from scratch. The Q&A loop, the round-3 checkpoint, the hard gates, and the advisory reviewer pass all still run; `--continue` does not lower the bar, only the starting cost.

When `INPUT_NOTES` is non-empty, the protocol skill pre-populates draft sections from that freeform brain-dump wherever the notes clearly map to a gated section, then focuses the rounds on the gaps and weak sections rather than re-eliciting every section from scratch. Seeded content is a *draft starting point*, not a confirmed answer: it never satisfies a hard gate on its own — every gated section the seed pre-fills is still confirmed (or sharpened) with the human in the rounds, and sections the notes do not cover are asked normally. `prior_doc` and `input_notes` are independent and may both be present in one session.

`draft_path=<DRAFT_PATH>` (resolved in Step 4d) is the gitignored scratch file for **intra-session autosave**. Per its **Autosave** section, the protocol skill writes the in-progress draft — the answered sections plus a round-state header — to that path with the platform's file-write tool **after every round**, so an interruption after any round is recoverable rather than losing every answer. If `DRAFT_PATH` already holds content (a resumed draft from Step 4d), the protocol skill loads it as starting context at round 1. The scratch file holds only draft prose: `.stride/` ignores itself (Step 4d), the file is never `git add`-ed, and it never carries the Stride API token or any other secret. Autosave is a recovery convenience, not a gate bypass — the hard gates, framing checkpoint, premortem, and reviewer pass still run in full.

The parsed value of `--profile` from Step 1 is threaded into the protocol skill as `profile=<PROFILE>`. It selects which forcing questions run inside the rounds and which optional sections the document may include. See the **Profiles** subsection of `skills/stride-ideation/SKILL.md` for the per-profile augmentations. `--profile=lean` (the default) runs the shared round loop with no augmentations; `--profile=product`, `--profile=discovery`, and `--profile=lean-startup` add advisory rubric checks and (for `product` and `lean-startup`) one optional section.

The protocol skill enforces:
- the hard gate against premature implementation,
- the round-based question loop (≤ 4 questions per round),
- the display-only round recap printed before every round (see **Round recap** in `skills/stride-ideation/SKILL.md`) — it reports per-section solid/thin/empty status and the round's target sections without changing the gate, the round order, or the question budget,
- the "I'm not sure — propose candidates" uncertainty path offered on every batched question — gated-section and profile-specific forcing questions alike (see **Uncertainty path** in `skills/stride-ideation/SKILL.md`); it proposes 2–4 topic-tailored candidates but can never satisfy the hard gate without human confirmation,
- the mandatory round-3 framing checkpoint,
- the mandatory round-4 premortem,
- the mandatory round-5 MVP design (lean-startup profile only),
- the mandatory challenge gate (run after the premortem — and after Round 5 under lean-startup — and before the reviewer pass) — its four components (assumption-confidence audit, blind-spot scan, two alternatives, trade-off analysis) are surfaced to the human via the Copilot CLI selection primitive as a multi-select: one option per low-confidence assumption, one per material blind spot, one per alternative worth pursuing, plus an explicit "Challenge nothing — write as-is" option; at most one refinement round follows the human's selection; the gate is profile-independent and advisory and never blocks the write, and its confidence ratings annotate Assumptions in place while its blind spots, alternatives, and trade-off table fold into the optional "Design challenge" section (see **Challenge gate** in `skills/stride-ideation/SKILL.md`),
- the seven hard-gated sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success Metrics),
- the advisory `requirements-reviewer` agent pass before the write — its findings are surfaced to the human as a selectable decision via the Copilot CLI selection primitive (each finding one line, severity-tagged, plus an explicit "Address none — write as-is" option) that feeds the at-most-one refinement round; an `approved` verdict with no findings shows no prompt, and the reviewer never blocks the write (see **Reviewer pass** in `skills/stride-ideation/SKILL.md`).

When the protocol skill returns, you will have a single string `DRAFT_DOC` containing the fully composed requirements markdown — every gated section present and substantive. If the protocol skill returns without a draft (user aborted, hard gate not satisfied), stop here and exit cleanly — do NOT write anything to disk and do NOT commit.

### Step 6: Conform the draft to the spec template

The protocol skill returns prose for each section but the on-disk format is fixed by the design spec's "Output: requirements markdown template". Ensure `DRAFT_DOC` looks like:

```markdown
# <Topic>

*Date: YYYY-MM-DD HH:MM*
*Session: <SESSION_TS>-<SLUG>*

## Problem
<one paragraph max>

## Goal
<outcome, not feature>

## Success metrics
- **leading indicators** (observable while the work is in flight, predict the outcome):
  - <bulleted, each measurable>
- **lagging indicators** (the outcome itself, observable only after it has occurred):
  - <bulleted, each measurable>

## Assumptions
*Ordered highest to lowest risk; the riskiest entry is marked `(R)` (or `**(riskiest)**`).*
- <riskiest assumption> (R)
- <next-riskiest assumption>
- <remaining assumptions, in decreasing risk>

## Constraints
- <bullets — non-negotiable>

## Non-goals
- <bullets, each with a reason>

## Outcome
<what the world looks like after this ships>

## Sketch
<optional; 1–5 paragraphs if present>

## Open questions
<optional; bullets of deferred items>
```

The seven hard-gated sections appear above the two optional ones (`Sketch`, `Open questions`). Include the optional sections only if the conversation produced substantive content for them. If the draft is missing any gated section, treat that as a protocol-skill bug and abort — do NOT paper over it by writing an incomplete doc.

**Decomposition seams (optional, freeform).** If the conversation surfaced that the work splits across multiple independent surfaces — separate plugins, separate services, separate repos that ship on their own cadences — append a freeform `## Decomposition seams` section after the optional sections. List each surface as a top-level numbered markdown item with a bold name, e.g. `1. **Kanban app** — owns the JSON contract`, `2. **stride plugin** — adapter for the reference workflow` (the preferred shape; the stride-ideation-stridify skill also accepts top-level `- **Name**` bullets, or `### Name` headings, when the section has no numbered items — one shape per section, and a sub-list indented under an item belongs to that item). The section is freeform and the protocol skill does NOT gate it. Its downstream consumer is `stride-ideation-stridify --goal <name|index>`: when a requirements doc has many surfaces, the user can activate the stride-ideation-stridify skill once per surface (`stridify <path> --goal 1`, `stridify <path> --goal 2`, …) to reduce per-dispatch prompt size and the blast radius of a single subagent failure. The stride-ideation-stridify skill also prints a one-line preflight advisory suggesting `--goal` when the section enumerates more than 3 surfaces. Producing a Decomposition seams section here is the natural way for the user to discover the partitioning flag.

**Under `profile=lean-startup` only**, append one more optional section after `## Open questions` — `## MVP / Validation experiment` — produced by the Round 5 MVP-design batch. Its sub-fields, in order:

- **Riskiest assumption being tested:** quote the `(R)`-marked entry from Assumptions verbatim.
- **Experiment design:** what to build, fake, or measure to produce the validating signal.
- **Success criteria:** observable signal that validates the assumption.
- **Failure criteria:** observable signal that falsifies the assumption.
- **Time box:** when results are expected.
- **Pivot-or-persevere decision:** what happens based on result.

This `MVP / Validation experiment` section is profile-conditional — under `lean`, `product`, or `discovery` it MUST NOT appear even if the user volunteered experiment-shaped content. The riskiest-assumption line is a quote of an existing Assumptions entry, not a freshly authored field; the other five sub-fields are authored from the Round 5 answers.

### Step 7: Verify the target path is still untaken

Re-run `sti_unique_path` with the same arguments as Step 4 and confirm the returned path equals `TARGET_PATH`:

```bash
(
# Carried forward: PLUGIN_ROOT, SESSION_TS, SLUG
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
SESSION_TS='<value of SESSION_TS>'
SLUG='<value of SLUG>'
[ -f "$PLUGIN_ROOT/lib/filename.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/filename.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
. "$PLUGIN_ROOT/lib/filename.sh"
sti_unique_path docs/ideation "$SESSION_TS" "$SLUG" requirements md
)
```

(PowerShell: `Sti-UniquePath docs/ideation <SESSION_TS> <SLUG> requirements md`.) If the printed path differs from `TARGET_PATH` (another process wrote a colliding file during the session), record the new value as `TARGET_PATH` and use it — never overwrite an existing file. This is the HARD INVARIANT documented in `lib/filename.sh`.

### Step 8: Write the file

Use the platform's file-write tool to write `DRAFT_DOC` to the resolved target path. The directory `docs/ideation/` may not exist on a fresh repo; create it via `mkdir -p docs/ideation` before the write if Step 4's path resolution depended on it.

### Step 9: Commit

```bash
(
# Carried forward: PLUGIN_ROOT, TARGET_PATH, SLUG, CONTINUE_PATH (empty unless --continue), DRAFT_PATH
PLUGIN_ROOT='<value of PLUGIN_ROOT>'
TARGET_PATH='<value of TARGET_PATH>'
SLUG='<value of SLUG>'
CONTINUE_PATH='<value of CONTINUE_PATH, or empty>'
DRAFT_PATH='<value of DRAFT_PATH>'
[ -f "$PLUGIN_ROOT/lib/draft.sh" ] || { echo "stride-ideation: cannot find the plugin helpers: $PLUGIN_ROOT/lib/draft.sh does not exist. PLUGIN_ROOT must be the directory two levels above skills/stride-ideation-ideate/SKILL.md." >&2; exit 1; }
. "$PLUGIN_ROOT/lib/draft.sh"

git add "$TARGET_PATH" || exit 1
if [ -n "${CONTINUE_PATH:-}" ]; then
  git commit -m "stride-ideation: refine requirements for $SLUG" -- "$TARGET_PATH" || exit 1
else
  git commit -m "stride-ideation: requirements for $SLUG" -- "$TARGET_PATH" || exit 1
fi

# The session succeeded — the committed doc supersedes the scratch draft.
# Delete the gitignored autosave file (sti_draft_clear / Sti-DraftClear) so no
# stale draft lingers to be offered for resume next time. Idempotent: a no-op
# if the draft was never written.
if [ -n "${DRAFT_PATH:-}" ]; then
  sti_draft_clear "$DRAFT_PATH"
fi
)
```

PowerShell: the same two `git` commands, then `Sti-DraftClear <DRAFT_PATH>` from `lib/draft.ps1`.

Commit message format: `stride-ideation: requirements for <slug>` (fresh) or `stride-ideation: refine requirements for <slug>` (continue). Do not include the session timestamp in the message — the filename already carries it.

The `sti_draft_clear "$DRAFT_PATH"` call (or `Sti-DraftClear` on Windows) runs **only after the commit succeeds** — the scratch draft is the recovery artifact, so it survives until the real doc is committed and is then removed so no stale autosave is offered for resume on a future run. The scratch file lives under the self-ignoring `.stride/` directory (Step 4d) and is never part of the commit's file list.

If the working tree had unrelated uncommitted changes before the session — **including changes the user had already staged** — the commit MUST include only the new requirements doc. `git add <path>` alone does not ensure that: a plain `git commit` records everything in the index, so a file staged before the session would ride along. That is why the block passes the doc as a pathspec after `--` (`git commit -m … -- "$TARGET_PATH"`), which commits only that path and leaves anything else staged exactly as it was. The `git add` stays: a pathspec commit of a not-yet-tracked file fails unless the file was added first. Never use `git add -A` or `git commit -a`. In `--continue` mode the source document MUST NOT appear in the commit's file list (it was not modified, so `git status` will already show it clean — but verify nothing accidental crept in).

### Step 10: Print the neutral terminal message

Print **exactly** these three lines, substituting the resolved path:

> Requirements written to `<TARGET_PATH>`.
> You can stop here — the doc is the deliverable.
> Or, to decompose this into Stride tasks and ship them in one shot, activate the `stride-ideation-stridify` skill against `<TARGET_PATH>` next.

Do NOT add follow-up suggestions, do NOT auto-activate the stride-ideation-stridify skill, do NOT propose implementation steps. The terminal state is the written document.

## What this skill does NOT do

- Decomposition into Stride tasks AND shipping to a Stride workspace in one shot — see `skills/stride-ideation-stridify/SKILL.md`.
- Modifying any file other than the new requirements doc — pre-existing files (including a `--continue` source document) are read-only.
