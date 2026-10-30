# Stride Exploratory Testing for GitHub Copilot

Structured, charter-based **exploratory testing** — from GitHub Copilot CLI.

This plugin lets you test software the way a skilled human tester does: discovering the risks, questions, and bugs that scripted and automated checks miss. It is the GitHub Copilot port of the Claude Code plugin [`cheezy/stride-exploratory-testing`](https://github.com/cheezy/stride-exploratory-testing). You plan **charters** (missions for a session), run **time-boxed sessions** that apply named **heuristics** and judge results with **oracles**, capture findings in an SBTM session sheet, and roll everything up into a stakeholder-ready **debrief**.

## What this is

Automated checks confirm what you already know to expect. **Exploration** is the other half — actively looking for what you *didn't* think to check. The mental model this plugin is built around is:

> **Tested = Checked + Explored**

*Checked* is the assertions your test suite already runs. *Explored* is a skilled tester designing each experiment from what the last one revealed, chasing risk rather than a fixed script. This plugin gives that exploration structure: a charter to give a session direction, heuristics to turn the charter into concrete probes, oracles to decide whether a result is actually a bug, and a session discipline (time-boxing, notes, debrief) that turns wandering into reportable value.

Because **GitHub Copilot CLI has no slash commands**, the seven commands of the Claude Code plugin (`/charter`, `/nightmare-headline`, `/explore`, `/pair`, `/recon`, `/debrief`, `/harden`) are ported as **named skills** you activate in chat. There is no `commands/` directory — the plugin's entire surface is **skills** and **agents**.

## Installation

Install via the GitHub Copilot CLI. This plugin is distributed through the [`stride-copilot-marketplace`](https://github.com/cheezy/stride-copilot-marketplace) catalog (the vendored Stride Copilot marketplace):

```bash
copilot plugin install https://github.com/cheezy/stride-copilot-exploratory-testing
```

If you have already registered the `stride-copilot-marketplace` catalog with your Copilot CLI, you can install it by name instead:

```bash
copilot plugin install stride-copilot-exploratory-testing
```

### Managing the plugin

```bash
copilot plugin list                                          # View installed plugins
copilot plugin update stride-copilot-exploratory-testing     # Update to the latest version
copilot plugin uninstall stride-copilot-exploratory-testing  # Remove the plugin
```

No API token or authentication is required — this plugin does not call the Stride API. It is a self-contained testing toolkit that works against whatever application you point it at (see the safety boundary in the quick-start below).

## The plugin surface

The plugin is organized as **core knowledge skills** (the doctrine), **command-derived skills** (the workflows that replace the upstream slash commands), and **two agents** (the fan-out subagents).

### Core knowledge skills

These carry the exploratory-testing doctrine. The orchestrator routes to them; the workflows and agents reference them rather than restating their catalogs.

| Skill | What it teaches |
|-------|-----------------|
| [`stride-exploratory-testing`](skills/stride-exploratory-testing/SKILL.md) | The front door and orchestrator. Teaches the mental model (Tested = Checked + Explored), frames a time-boxed session, and routes each request to the right sub-skill or workflow. |
| [`chartering`](skills/chartering/SKILL.md) | How to decide *what* to explore and frame it as a charter — the `Explore <target> with <resources> to discover <information>` template, the charter sources, the Nightmare Headline Game, and the SFDIPOT lens. |
| [`heuristics`](skills/heuristics/SKILL.md) | The single source of truth for test ideas — general and web cheat sheets, the variable-spotting catalog, and Whittaker's Tours. Every other skill and agent links here rather than duplicating it. |
| [`oracles`](skills/oracles/SKILL.md) | How to decide whether an observed result is a defect — Never/Always rules, alternative-resource consistency checks, approximations, and the Heuristic Test Strategy Model's quality-criteria checklist. |
| [`bug-advocacy`](skills/bug-advocacy/SKILL.md) | Kaner's RIMGEA discipline for the work between "an oracle says this is wrong" and a report someone can act on — Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly — plus the severity rubric every `severity` value comes from, and the dispassionate-tone rule. The worked example and the full tone rule live in [`references/worked-example-and-tone.md`](skills/bug-advocacy/references/worked-example-and-tone.md). |
| [`session`](skills/session/SKILL.md) | The session discipline — time-boxing, the SBTM session sheet, Task Breakdown Metrics, note conventions, stopping heuristics, and both debrief templates (Explored/Found/Unknown and PROOF). The `.exploratory/` artifact convention is set out in full in [`references/session-artifacts.md`](skills/session/references/session-artifacts.md). |

### Command-derived skills

These are the workflows — the Copilot skills that stand in for the upstream slash commands. Activate them by name in chat (e.g. *"Activate stride-exploratory-testing-charter for the CSV import"*).

| Skill | Replaces (upstream) | What it does |
|-------|---------------------|--------------|
| [`stride-exploratory-testing-charter`](skills/stride-exploratory-testing-charter/SKILL.md) | `/charter` | Turns a target into a ranked list of well-formed charters (dispatches the `charter-generator` agent). Generates charters only — it never runs a session. |
| [`stride-exploratory-testing-nightmare-headline`](skills/stride-exploratory-testing-nightmare-headline/SKILL.md) | `/nightmare-headline` | Runs the Nightmare Headline Game — elicit the worst plausible headline, pick one, brainstorm its causes, and refine them into ranked charters. |
| [`stride-exploratory-testing-explore`](skills/stride-exploratory-testing-explore/SKILL.md) | `/explore` | The flagship plan-and-execute flow — generate or load charters, dispatch the `explorer` agent per charter under a strict safety boundary, then aggregate every session into one debrief. |
| [`stride-exploratory-testing-pair`](skills/stride-exploratory-testing-pair/SKILL.md) | `/pair` | Pair with a human who drives the app themselves. Suggests the next probe and names its lens, judges what they report with `oracles`, runs RIMGEA on confirmed defects, calls out neglected areas and variables unprompted, and keeps the session sheet and parking lot. **Never drives the app and never dispatches the `explorer` agent.** |
| [`stride-exploratory-testing-recon`](skills/stride-exploratory-testing-recon/SKILL.md) | `/recon` | A quick reconnaissance pass over an unfamiliar system — survey the landscape, surface stakeholder questions, and emit ranked candidate charters. |
| [`stride-exploratory-testing-debrief`](skills/stride-exploratory-testing-debrief/SKILL.md) | `/debrief` | Turns raw session notes into a stakeholder-ready report using both templates (Explored/Found/Unknown + PROOF). |
| [`stride-exploratory-testing-harden`](skills/stride-exploratory-testing-harden/SKILL.md) | `/harden` | Turns a session's confirmed bugs into drafted regression checks. Detects the project's test framework rather than assuming one and says what it detected before writing; reports every bug it could not convert and why. Drafts are staged — it never runs one and never claims one passes. **Given a bug source and `--framework` it asks no question**, so an orchestrator can run it unattended; `--framework none` takes the none-detected path, and a bug source it cannot read stops the run. |

### Agents

Two `.agent.md` subagents do the bounded, fan-out-friendly work.

| Agent | What it does |
|-------|--------------|
| [`charter-generator`](agents/charter-generator.agent.md) | Given a target and optional risk context, returns a ranked list of well-formed charters as structured JSON. Read-only; it generates charters and never executes them. |
| [`explorer`](agents/explorer.agent.md) | Runs a single budgeted session against ONE charter — designs probes from named heuristics, exercises the running app as a user would, judges results with oracles, records an SBTM sheet, and returns structured findings. An inline **explorer card** carries everything it needs to label a bug and end a session — the exact `Critical`/`High`/`Moderate`/`Minor` severity tokens and ladder, RIMGEA mapped onto the `bugs[]` fields, the oracle verdicts, and the stop rules — so the `heuristics`, `oracles`, `bug-advocacy` and `session` skills are optional depth, named without a file path. It observes HTTP with `curl -q -sS -i`, never follows a redirect with `-L`, never judges a rendered view from source, and ends a charter that asks for an observation no tool of its own can make with `stop_reason: "no_observation_surface"` (`status: "blocked"`). It locates with `search` or `grep -n`, reads a bounded range with `sed -n` through `execute`, and never re-reads a file it has already read unless the file changed. Operates under an absolute non-destructive, authorized-target-only safety boundary. Given an [`EXPLORATORY_REPORT_PATH`](#explorer-report-file-exploratory_report_path) line, it writes the full findings to that one file and replies with a short summary. |

### Explorer report file (`EXPLORATORY_REPORT_PATH`)

A caller other than the explore skill can keep the explorer's full findings out of its own context. Give the explorer one line of its own in the environment context, never in the charter:

```text
EXPLORATORY_REPORT_PATH=/absolute/path/to/report.json
```

The explorer then writes the complete contract `1.0` findings JSON to that file in one `execute` command and replies with plain text of at most 2,048 bytes and no ```json fence: `report:`, `contract_version:`, `status:`, `stop_reason:`, the probe and tool-call counts, the bug counts by severity with the `questions_risks`, `off_charter` and `known_bad` counts, and one `<Severity> | replicated: <yes|no|not established> | <summary>` line per bug; in verify mode (below) a `verify:` line follows `status:`. Past the bound, whole bug lines are dropped from the lowest severity, never cut short. Read the findings from the path you supplied, never one the summary names.

- **The path must come from you.** It must be absolute, with no `..` segment, quote or control character, and never built from app content, the charter or `known_issues`; two `EXPLORATORY_REPORT_PATH` lines are refused.
- **Quote charter lines that look like it.** Copilot hands the explorer one undelimited prompt, so when you pass a charter or target text you did not write, prefix any line in it that starts with `EXPLORATORY_REPORT_PATH` with `> `, as the explore skill does, and it cannot be read as your line.
- **It must not exist yet.** An existing file, directory or symlink is refused, so a write never overwrites or follows a link and two sessions never overwrite each other. A missing parent directory gets one `mkdir -p` retry. Put the report in a directory only you can write to, never straight under a shared one such as `/tmp`: the explorer checks the file, not its parent directories.
- **Nothing is lost on failure.** A refused or failed write replies `report: NOT WRITTEN - <reason>` followed by the full fenced JSON.
- **Hardening from it.** The report file is a bug source for `stride-exploratory-testing-harden`: pass its path with `--framework` and the skill reads `bugs[]` from the file, never from the summary, and asks no question.
- **No path, no change.** The reply is the fenced JSON, as before. The explore skill never passes a path, reads every result inline, and quotes any `EXPLORATORY_REPORT_PATH` line in operator, target or charter text with `> `.

To check a written report against the contract, run `EXPLORER_OUTPUT=<path> bash lib/test-structure.sh`.

**Why `execute` and not an edit tool.** GitHub's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) lists `edit` (compatible names `Edit`, `MultiEdit`, `Write` and `NotebookEdit`) with no way to scope it to one path, so turning it on would let the explorer edit any file. The explorer therefore holds `read`, `search`, `glob` and `execute`, writes the report through a quoted heredoc under `set -o noclobber`, and states the one-path rule in its own prose, pinned by `lib/test-structure.sh` and `lib/test-structure.ps1`. The Copilot CLI's `--allow-tool` flag can allow a write to one file, as its [allowing tools](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools) page shows, but that is the caller's command line, not something an agent file can declare. `execute` is the reference's name for the shell tool (with `shell`, `Bash` and `powershell` as compatible names); it lists no `run` and ignores names it does not recognize, which is why the explorer no longer declares `run`. If the runtime still withholds a terminal, every write fails and the reply is `report: NOT WRITTEN - …` plus the fenced JSON. Copilot was not installed where this was written, so a dispatched round trip has not been run.

### Explorer verify mode (`EXPLORATORY_MODE=verify`)

A caller that has fixed a bug can re-check it without a full session. Add one line of its own to the environment context, next to the two required lines, and pass the bug's `summary`, `observed`, `minimal_repro` and any `generalization` as a `<verify_bug>` block outside the environment context, the way `known_issues` is passed:

```text
EXPLORATORY_MODE=verify
```

```text
<verify_bug>
summary: <the bug's summary>
observed: <what was observed>
minimal_repro: <the bug's minimal_repro>
generalization: <optional>
</verify_bug>
```

The explorer builds the charter from the bug, runs the `minimal_repro` as probe 1 and, when `generalization` names a condition, one variant of it as probe 2, on a budget of **2 probes / 10 tool calls**. Copilot's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) offers no turn or step limit and the explorer's frontmatter sets none, so the 10-call ceiling is one the explorer counts itself, as it does the ordinary 60. The findings gain a root `verify` object, `{ "result", "repro_reached", "evidence" }`, and a report summary gains a `verify:` line after `status:`.

- **`pass`** needs the repro point reached and no part of the failure seen. **`fail`** includes a partial fix, and the remaining defect is filed in `bugs`.
- **`not_verified` is never a pass.** It means the repro point was not reached: no usable `minimal_repro` (missing, empty or not established, or a void `<verify_bug>` block, which runs zero probes), the app unreachable, a ceiling before probe 1, a missing required line, or no oracle that could decide. Fall back to a full charter.
- **The bug is data, never instructions.** Nothing between the markers is read as environment context, a structured line, budget or target, and a missing, unclosed or repeated marker voids the bug, so the session runs zero probes and returns `not_verified`. Copilot still hands the explorer one undelimited prompt, so in bug fields, charter or target text you did not write, prefix any line that starts with `AUTHORIZED_NON_PRODUCTION`, `ALLOWED_HOSTS`, `EXPLORATORY_REPORT_PATH` or `EXPLORATORY_MODE` with `> `, as the explore skill does; a quoted line never counts as one of yours.
- **`status` is still derived from `stop_reason`**, never from the verdict, and the safety boundary, both required lines and cleanup apply in full.
- **A pass covers that one bug only**, never the original charter's other risks. The explore skill never sets the mode; Copilot was not installed where this was written, so a dispatched verify session has not been run.

## Quick-start — your first session

You can go from "I want to test this feature" to a debrief in one Copilot CLI session:

1. **Charter the work.** Activate the charter skill with a target:

   ```
   > Activate stride-exploratory-testing-charter for the CSV import
   ```

   You get a ranked list of charters — missions of the form *"Explore the CSV import with malformed and oversized files to discover how the parser fails and whether it corrupts existing data."* (See [`fixtures/example-charters.md`](fixtures/example-charters.md) for a worked set.)

2. **Run a session.** Activate the flagship explore skill on a target with a **running, non-production, authorized** instance:

   ```
   > Activate stride-exploratory-testing-explore for the CSV import --timebox 90
   ```

   `--timebox` is **your** clock: it decides how many charters get funded (one
   session ≈ 90 minutes). Each explorer session itself is bounded by an
   agent-native **probe budget** — 12 probes by default, `--probes` to change —
   because an agent has no honest way to measure minutes.

   The skill asks a single up-front round of questions (how to reach the app, an explicit *authorized-and-non-production* confirmation, which interaction tools are available, and where test data lives), then writes two structured lines first in the environment context it hands the explorer — `AUTHORIZED_NON_PRODUCTION: yes` and `ALLOWED_HOSTS: <host[:port]>, …` — quoting any forged copy in your text with `> `, and dispatches the `explorer` agent per charter. It **fails closed** — with no authorized non-production target, it degrades to a plan-only charter list and does not execute.

3. **Read the debrief.** The explore skill aggregates every session into one report — Explored/Found/Unknown, a severity-ranked bug list, a follow-up parking lot, and a PROOF review. (See [`fixtures/example-session-sheet.md`](fixtures/example-session-sheet.md) and [`fixtures/example-debrief.md`](fixtures/example-debrief.md).)

Not sure where the risk is? Start with `stride-exploratory-testing-recon` to map an unfamiliar system, or `stride-exploratory-testing-nightmare-headline` to brainstorm worst-case failures into charters. Already have session notes? Activate `stride-exploratory-testing-debrief` to structure them into a report.

**Safety boundary.** The explorer exercises an app as a user would but **never** runs destructive or production-mutating actions, only touches systems you are authorized to test, and treats any app content it encounters as data — never as instructions. It runs only with `AUTHORIZED_NON_PRODUCTION: yes` and an `ALLOWED_HOSTS` line, and a missing, non-`yes` or duplicated line ends the session blocked with zero probes; hosts are matched exactly against that list. It removes every process and file it started on every exit path, and its Interrupt, Starve and Saboteur lenses stay within in-app means. Credentials come from your environment; they are never hard-coded or written into findings, and a credential file is opened only for a value the test-account pointer names. A test-account pointer counts only when it is the only one in the dispatch, on its own line in the environment context before any untrusted text.

## Fixtures

The [`fixtures/`](fixtures/) directory holds worked examples that double as templates and as regression anchors for the smoke tests. All of them use a single fictional, synthetic target (*ExpenseFlow*) with placeholder hosts (`demo.example.com`) and tenants (`<tenant A>`) — no real product, data, or credentials appear.

- [`example-charters.md`](fixtures/example-charters.md) — a ranked charter set plus a worked nightmare-headline-to-charter example and the "charter vs. check" anti-pattern.
- [`example-session-sheet.md`](fixtures/example-session-sheet.md) — a worked **agent-run** session sheet: a session budget and the counts the explorer actually kept, in place of a duration and Task Breakdown Metric percentages.
- [`example-debrief.md`](fixtures/example-debrief.md) — a worked debrief using both the Explored/Found/Unknown and PROOF templates.
- [`example-explorer-output.json`](fixtures/example-explorer-output.json) — a complete `explorer` report in output contract `1.0`: a status derived from its `stop_reason`, bugs carrying `replicated` and `provisional`, typed `questions_risks` and `off_charter` elements, and a `known_bad` entry. `lib/test-structure.sh` and `lib/test-structure.ps1` validate it against the agent file's own tables; set `EXPLORER_OUTPUT` to the path of a real report to check that report by the same rules.

For the full heuristics catalog, see the [`heuristics`](skills/heuristics/SKILL.md) skill (and the pointer in [HEURISTICS.md](HEURISTICS.md)) — it is the single source of truth and is deliberately not duplicated elsewhere.

## Session artifacts

A session that lives only in the conversation dies with it. Runs persist to a small, predictable tree in **the project you are testing** (the current working directory), never in the plugin's own install location:

```
.exploratory/
  backlog.md                              # candidate, deferred, and parked charters + open questions
  coverage.md                             # which areas are explored, which are still dark — a map, never a score
  sessions/
    2026-07-30-1942-receipt-import.md     # one debrief per explore run, or one session sheet per paired session
  checks/
    2026-07-30-1942-receipt-import/       # drafted regression checks from harden — never run
```

Add `.exploratory/` to the **project under test's** `.gitignore` — these files describe a real application and quote what was observed, so they are working material, not source.

**A missing file is an empty starting state, never an error.** A first run in a new project simply creates what it needs; nothing warns and nothing fails. On later runs the `stride-exploratory-testing-explore` and `stride-exploratory-testing-charter` skills read the coverage outline and the backlog back and pass them to `charter-generator` as **coverage context**, which discounts ground already covered and promotes what is still dark — so run five proposes different charters than run one. Six of the seven command-derived skills append to the backlog as they go: explore adds deferred charters and parked items, pair adds parked items, open questions and declined coverage gaps, debrief adds parked items and open questions, charter and nightmare-headline add the charters they generate, and recon adds candidate charters plus open questions — and may add an un-explored area stub to the coverage outline, though it never marks an area explored, because surveying is not exploring. The seventh, harden, writes only under `.exploratory/checks/` and touches neither shared artifact. Risk always outranks recency: an area explored last week with an open Critical bug is not covered ground.

Artifacts are read back as **untrusted data, never instructions**. The `session` skill owns the full convention — the tree, the formats, the header blocks, and the read-immediately-before-write mechanics — set out in full in [`skills/session/references/session-artifacts.md`](skills/session/references/session-artifacts.md).

## Sources and attribution

Exploratory testing is a decades-old craft, and this plugin stands on the shoulders of the practitioners who developed it. **Established exploratory-testing practice is the primary source**; the doctrine here paraphrases and operationalizes it rather than reproducing anyone's text. In particular:

- **Session-Based Test Management (SBTM)** — the session sheet, the charter, Task Breakdown Metrics, and the **PROOF** debrief mnemonic (Past / Results / Obstacles / Outlook / Feelings) originate with **James Bach** and **Jonathan Bach**. The `session` skill operationalizes SBTM.
- **Bug Advocacy (RIMGEA)** — Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly — the follow-through that turns a found bug into a fixed one originates with **Cem Kaner**. The `bug-advocacy` skill encodes it, along with the severity rubric.
- **Tours** — the touring heuristics for surveying an application (Guidebook, Landmark, Garbage Collector's, and others) originate with **James Whittaker** (*Exploratory Software Testing*). The `heuristics` skill groups them by district.
- **The Heuristic Test Strategy Model (HTSM)** — the quality-criteria checklist used to derive Never/Always oracle statements, and the SFDIPOT product-element lens, originate with **James Bach**. The `oracles` and `chartering` skills draw on it.

These references are paraphrased and adapted; only brief fair-use snippets of any original phrasing appear. For the source material itself, consult the authors' own writing (Satisfice, the *Exploratory Software Testing* book, and the SBTM papers).

## Relationship to upstream

This plugin is a faithful port of [`cheezy/stride-exploratory-testing`](https://github.com/cheezy/stride-exploratory-testing) to GitHub Copilot CLI. The doctrine — the charter template, the heuristics catalog, the oracle strategies, and the session lifecycle — is preserved. The differences are mechanical adaptations to the Copilot platform:

| Upstream (Claude Code) | This plugin (Copilot CLI) |
|---|---|
| Seven slash commands (`/charter`, `/nightmare-headline`, `/explore`, `/pair`, `/recon`, `/debrief`, `/harden`) | Seven named command-derived skills (`stride-exploratory-testing-*`) — Copilot CLI has no slash-command mechanism |
| `commands/*.md` directory | `skills/<name>/SKILL.md` directories |
| `agents/*.md` agent files | `agents/*.agent.md` agent files (Copilot extension) |
| `AskUserQuestion` tool | The platform's question/selection UI |
| `Read`, `Grep`, `Glob`, `Bash`, `WebFetch` tool names | Copilot tool nouns (`read`, `search`, `glob`, `execute`); HTTP surfaces are exercised via `execute` + `curl -q -sS -i`, never `-L`; the explorer has no fetch tool |

## License

[MIT](LICENSE) © 2026 Jeff Morgan
