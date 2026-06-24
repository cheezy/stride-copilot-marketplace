# Stride Ideation for GitHub Copilot

Turn an idea into shipped Stride tasks — from GitHub Copilot CLI.

This plugin provides brainstorming and ideation skills for projects that use [Stride](https://www.stridelikeaboss.com). It is the GitHub Copilot port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) (Claude Code). Activate the `stride-ideation-ideate` skill to drive an interactive ideation session that produces a committed requirements markdown document. Stop there if you just want a written spec — or activate the `stride-ideation-stridify` skill to decompose the requirements into a Stride batch JSON, commit it for audit, and POST it to the Stride API in a single invocation.

## Overview

The two skills:

```text
stride-ideation-ideate [<topic>] [--continue <path>] [--input <path>] [--profile <name>]
  Interactive ideation session. Drives a Q&A loop with you to produce a
  timestamped requirements markdown doc. Stop here if you only want a spec.
  --continue refines a prior committed requirements doc; --input seeds draft
  sections from a freeform brain-dump file (read-only). When --profile is
  omitted, the session recommends one before the rounds. See "Session
  experience" below.

stride-ideation-stridify <path-to-requirements.md> [--goal <name|index>] [--yes]
  End-to-end pipeline: validates the requirements doc, preflights auth,
  dispatches the decomposer agent, stamps audit metadata, writes and
  commits a sibling Stride batch JSON, then — after showing you the decomposed
  goal/task tree and getting your approval — POSTs it to /api/tasks/batch on
  your Stride instance and renders the created G/W identifiers.
  --goal scopes the dispatch to one surface from the doc's
  ## Decomposition seams section (see the upstream "Resilience model" below).
  --yes / --auto-approve bypasses the approval gate for scripted callers.
```

The first skill is hard-gated on seven required sections (Goal, Problem, Outcome, Assumptions, Constraints, Non-goals, Success metrics) plus shape requirements on Assumptions (ranked, riskiest marked, premortem-derived) and Success metrics (both leading and lagging indicators). The second skill is gated on a passing structural validation of the decomposer's output before it commits or POSTs anything.

## Installation

Install via the Copilot CLI plugin command:

```bash
copilot plugin install https://github.com/cheezy/stride-copilot-ideation
```

### Plugin Management

```bash
copilot plugin list                                   # View installed plugins
copilot plugin update stride-copilot-ideation         # Update to latest version
copilot plugin uninstall stride-copilot-ideation      # Remove plugin
```

### Auth file

The `stride-ideation-stridify` skill reads `.stride_auth.md` in the project root to obtain `STRIDE_API_URL` and `STRIDE_API_TOKEN`. Create it once per project:

```markdown
- **API URL:** `https://www.stridelikeaboss.com`
- **API Token:** `stride_dev_abc123...`
```

Add `.stride_auth.md` to your project's `.gitignore` — it contains a secret.

## Usage

### `stride-ideation-ideate` — drive a session, produce a requirements doc

Activate the skill in chat with an inline topic or with the topic via the platform's question UI:

```
> Activate stride-ideation-ideate with "Add notifications system"
```

The skill drives a round-based question loop (≤ 4 questions per round) and gates the seven required sections before writing. The terminal state is a committed `docs/ideation/<timestamp>-<slug>-requirements.md` file. Profiles are selected via `--profile lean|product|discovery|lean-startup`; the default `lean` matches upstream v0.3.0 behavior.

```
> Activate stride-ideation-ideate with "--profile=product Review queue UX"
> Activate stride-ideation-ideate with "--continue docs/ideation/2026-05-12T120000-foo-requirements.md"
```

### `stride-ideation-stridify` — decompose + POST to Stride

After ideating (or against any compatible requirements doc), activate the second skill against the requirements path:

```
> Activate stride-ideation-stridify with docs/ideation/2026-05-12T120000-foo-requirements.md
```

The skill validates the seven required sections, preflights auth from `.stride_auth.md`, dispatches the `requirements-decomposer` agent (with a bounded 3-attempt retry on transient failures), stamps `source_spec` + `source_spec_sha256` at the JSON root, writes a sibling `*-stride-batch.json` to disk, commits it, then POSTs to `/api/tasks/batch` and renders the created G/W identifier table.

When the requirements doc has many surfaces (`## Decomposition seams` with > 3 items), partition with `--goal`:

```
> Activate stride-ideation-stridify with <path> --goal kanban-app
> Activate stride-ideation-stridify with <path> --goal 2
```

Each `--goal` run produces a sibling batch JSON named `<source-slug>-<goal-slug>-stride-batch.json`.

## Session experience (v0.2.0+)

`stride-ideation-ideate` is a guided, recoverable, human-in-control session. These affordances are additive — a flag-free or `--profile=lean` run still produces the same committed requirements doc. All interaction uses the Copilot CLI platform's question/selection UI.

| Feature | What it does |
|---|---|
| **Round recap** | Before every round, a display-only recap shows each of the seven gated sections as `solid` / `thin` / `empty` plus the round's target sections. Never a question; never changes the gate, round order, or question budget. |
| **"I'm not sure — propose candidates"** | Every gated-section and forcing question carries this option. Picking it makes the skill propose 2–4 concrete, topic-tailored candidates with one-line rationales; you pick, edit, or ask for more. A proposed candidate never satisfies the gate until you confirm it. |
| **Profile recommendation** | When `--profile` is omitted, a single recommendation question runs before the rounds (recommended-first, lean default). Explicit `--profile` skips it. |
| **`--input <file>` brain-dump seed** | Reads a freeform notes file **read-only** and pre-populates draft sections, then focuses the rounds on the gaps. Distinct from `--continue` and composable with it. The input file is never modified, moved, or committed. |
| **Draft autosave & resume** | The in-progress draft is autosaved after every round to a **gitignored** scratch file under `.stride/`. On start, an unfinished draft for the same slug is detected and you're offered resume-or-fresh; the scratch file is deleted after a successful commit. Never holds the Stride API token. |
| **Reviewer decision** | When the advisory `requirements-reviewer` reports findings, they're surfaced as a selectable decision (severity-tagged) with an explicit **"Address none — write as-is"** choice. You choose what feeds the single refinement round. At most one refinement round; the reviewer never blocks the write. |

## Preview-and-approval gate on `stride-ideation-stridify` (v0.2.0+)

Before POSTing the generated batch to your Stride instance, the skill renders the decomposed goal/task tree (each goal title, its task count and titles, and the cross-goal claim order from `decomposition_notes`) and requires your explicit approval. The batch JSON is written and committed to disk *before* the gate, so on decline the skill stops cleanly (exit 0) with the audited artifact intact and no POST. Pass `--yes` / `--auto-approve` (explicit only, never inferred) to bypass the gate for scripted callers. The preview reads only the on-disk JSON and never prints the API token.

## How this plugin relates to `stride-copilot`

[`stride-copilot`](https://github.com/cheezy/stride-copilot) and `stride-copilot-ideation` are sibling plugins with different scopes:

- **`stride-copilot`** handles the **task lifecycle** — claiming a task from a backlog, decomposing goals, executing the four-stage hook workflow (`before_doing` / `after_doing` / `before_review` / `after_review` / `after_goal`), and completing tasks back to the Stride API.
- **`stride-copilot-ideation`** (this plugin) handles **ideation** — turning a fuzzy idea into a requirements doc, decomposing that doc into a Stride batch, and seeding the Stride backlog.

A typical full-loop usage installs both:

```bash
copilot plugin install https://github.com/cheezy/stride-copilot
copilot plugin install https://github.com/cheezy/stride-copilot-ideation
```

Then: activate `stride-ideation-ideate` to scope the work, activate `stride-ideation-stridify` to seed the backlog, then activate `stride-workflow` (from stride-copilot) to claim and ship the resulting tasks.

## How this plugin relates to upstream `stride-ideation`

This plugin is a faithful port of [`cheezy/stride-ideation`](https://github.com/cheezy/stride-ideation) to GitHub Copilot CLI — v0.1.0 ported upstream v0.7.0, and **v0.2.0 ports the upstream v0.8.0 feature set** (per-round recap, "I'm not sure" uncertainty path, profile recommendation, `--input` seed, draft autosave/resume, reviewer-findings decision, and the `stridify` preview-and-approval gate with `--yes`). The protocol — round-based question batching, hard-gated sections, advisory reviewer pass, decomposer dispatch with bounded retry, retry-exhaustion fallback, source_spec stamping, validator-before-commit, never-retry-POST — is preserved verbatim. The differences are mechanical adaptations:

| Upstream (Claude Code) | This plugin (Copilot CLI) |
|---|---|
| Two slash commands (`/stride-ideation:ideate`, `/stride-ideation:stridify`) | Two named skills (`stride-ideation-ideate`, `stride-ideation-stridify`) — Copilot CLI has no slash-command mechanism |
| `commands/*.md` directory | `skills/<name>/SKILL.md` directories |
| `agents/*.md` agent files | `agents/*.agent.md` agent files (Copilot extension) |
| `AskUserQuestion` tool name | "platform's question UI" / selection primitive — Copilot's question mechanism (recap, uncertainty path, profile recommendation, reviewer decision, and stridify gate all use it) |
| `Bash`, `Read`, `Write`, `Skill`, `Agent` tool names | Inferred via skill body (Copilot auto-resolves) |
| `lib/filename.sh` only | `lib/filename.sh` + `lib/filename.ps1` mirror for Windows users |
| `lib/test-*.sh` only | `lib/test-*.sh` + `lib/test-*.ps1` mirrors for Windows users |

The fixtures, the decomposer agent prompt, the reviewer agent rubric, and the lib/ helpers' Python scripts are byte-identical to upstream.

## Re-running the interactive end-to-end test

To verify the plugin works against your Copilot CLI install:

1. Activate `stride-ideation-ideate` with a small topic (e.g. "Add a dark-mode toggle"). Walk through the Q&A loop. Confirm a `docs/ideation/<timestamp>-dark-mode-toggle-requirements.md` is committed.
2. Activate `stride-ideation-stridify` against that committed path. Confirm a sibling `*-stride-batch.json` is committed and the G/W identifier table is rendered. (Use a non-prod Stride workspace — the POST creates real tasks.)
3. Run the smoke test suite: `bash lib/run_smoke_test.sh` (or `pwsh -File lib\run_smoke_test.ps1` on Windows). All stages should pass.

## License

MIT. See [LICENSE](./LICENSE).
