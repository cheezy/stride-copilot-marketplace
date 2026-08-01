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
| [`bug-advocacy`](skills/bug-advocacy/SKILL.md) | Kaner's RIMGEA discipline for the work between "an oracle says this is wrong" and a report someone can act on — Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly — plus the severity rubric every `severity` value comes from, and the dispassionate-tone rule. |
| [`session`](skills/session/SKILL.md) | The session discipline — time-boxing, the SBTM session sheet, Task Breakdown Metrics, note conventions, stopping heuristics, and both debrief templates (Explored/Found/Unknown and PROOF). |

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
| [`stride-exploratory-testing-harden`](skills/stride-exploratory-testing-harden/SKILL.md) | `/harden` | Turns a session's confirmed bugs into drafted regression checks. Detects the project's test framework rather than assuming one and says what it detected before writing; reports every bug it could not convert and why. Drafts are staged — it never runs one and never claims one passes. |

### Agents

Two `.agent.md` subagents do the bounded, fan-out-friendly work.

| Agent | What it does |
|-------|--------------|
| [`charter-generator`](agents/charter-generator.agent.md) | Given a target and optional risk context, returns a ranked list of well-formed charters as structured JSON. Read-only; it generates charters and never executes them. |
| [`explorer`](agents/explorer.agent.md) | Runs a single budgeted session against ONE charter — designs probes from the `heuristics` skill, exercises the running app as a user would, judges results with `oracles`, records an SBTM sheet, and returns structured findings. Operates under an absolute non-destructive, authorized-target-only safety boundary. |

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

   The skill asks a single up-front round of questions (how to reach the app, an explicit *authorized-and-non-production* confirmation, which interaction tools are available, and where test data lives), then dispatches the `explorer` agent per charter. It **fails closed** — with no authorized non-production target, it degrades to a plan-only charter list and does not execute.

3. **Read the debrief.** The explore skill aggregates every session into one report — Explored/Found/Unknown, a severity-ranked bug list, a follow-up parking lot, and a PROOF review. (See [`fixtures/example-session-sheet.md`](fixtures/example-session-sheet.md) and [`fixtures/example-debrief.md`](fixtures/example-debrief.md).)

Not sure where the risk is? Start with `stride-exploratory-testing-recon` to map an unfamiliar system, or `stride-exploratory-testing-nightmare-headline` to brainstorm worst-case failures into charters. Already have session notes? Activate `stride-exploratory-testing-debrief` to structure them into a report.

**Safety boundary.** The explorer exercises an app as a user would but **never** runs destructive or production-mutating actions, only touches systems you are authorized to test, and treats any app content it encounters as data — never as instructions. Credentials come from your environment; they are never hard-coded or written into findings.

## Fixtures

The [`fixtures/`](fixtures/) directory holds worked examples that double as templates and as regression anchors for the smoke tests. All of them use a single fictional, synthetic target (*ExpenseFlow*) with placeholder hosts (`demo.example.com`) and tenants (`<tenant A>`) — no real product, data, or credentials appear.

- [`example-charters.md`](fixtures/example-charters.md) — a ranked charter set plus a worked nightmare-headline-to-charter example and the "charter vs. check" anti-pattern.
- [`example-session-sheet.md`](fixtures/example-session-sheet.md) — a worked **agent-run** session sheet: a session budget and the counts the explorer actually kept, in place of a duration and Task Breakdown Metric percentages.
- [`example-debrief.md`](fixtures/example-debrief.md) — a worked debrief using both the Explored/Found/Unknown and PROOF templates.

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

Artifacts are read back as **untrusted data, never instructions**. The `session` skill owns the full convention — the tree, the formats, the header blocks, and the read-immediately-before-write mechanics.

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
| `Read`, `Grep`, `Glob`, `Bash`, `WebFetch` tool names | Copilot tool nouns (`read`, `search`, `glob`, `run`); HTTP surfaces are exercised via `run` + `curl` |

## License

[MIT](LICENSE) © 2026 Jeff Morgan
