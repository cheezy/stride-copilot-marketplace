# Smoke Test — stride-copilot-security-review

This document describes the manual end-to-end verification procedure for the ported plugin. Run it after each change to the agent prompt, the `security-review-essentials` skill or the rule packs and mode files beside it (`skills/security-review-essentials/packs/` and `modes/`), or the plugin manifest, and before publishing a new release.

The smoke test exercises **two fixtures**: one that MUST produce a finding (positive control) and one that MUST NOT (negative control). Together they confirm that the agent fires when it should and stays quiet when it should — the minimum signal that the plugin is loaded correctly and the agent prompt has not regressed.

> This document is a procedure, not a passed test. The Copilot CLI smoke test must be run by a human in a real Copilot CLI session — it has not been exercised from within an automated workflow.

## 1. Prerequisites

- **Copilot CLI** installed and on `$PATH`. Verify with `copilot --version`.
- **A test repository** initialized with `git init` somewhere on your filesystem. The skill scopes its review by `git diff HEAD` or `git ls-files`, so the procedure needs an actual git working tree to run against.
- **The plugin installed locally.** From the repository root of this plugin checkout (`stride-copilot-security-review/`), run:

  ```bash
  copilot plugin install .
  ```

  (Alternatively, install from the remote: `copilot plugin install https://github.com/cheezy/stride-copilot-security-review`.)

  Verify with `copilot plugin list` — `stride-copilot-security-review` should appear with the version from `plugin.json` (currently `0.1.0`).

- **The fixture files copied into your test repository.** The positive- and negative-control fixtures live in this plugin's `test/fixtures/` directory; copy them into your test repository's working tree before running the procedure:

  ```bash
  cp /path/to/stride-copilot-security-review/test/fixtures/command_injection.rb     ./
  cp /path/to/stride-copilot-security-review/test/fixtures/phoenix_fragment_safe.ex ./
  git add command_injection.rb phoenix_fragment_safe.ex
  ```

  Do NOT modify the fixtures — they are the spec; the agent must match `EXPECTED.md` for the procedure to be meaningful.

## 2. Positive-control test (`command_injection.rb`)

This fixture is HTTP-handler Ruby that interpolates a user-supplied filename directly into a shell command without escaping. The Ruby/Rails framework pack and the universal `injection` class should both flag it.

**Procedure:**

1. Stage the fixture (`git add command_injection.rb`) so it shows up in the diff.
2. Activate the `security-review-essentials` skill in Copilot CLI with no arguments (diff mode is the default).
3. Wait for the review to complete and print its report.

**Expected outcome:**

Per `test/fixtures/EXPECTED.md`, the agent must produce at least one finding with:

- `severity` = `critical`
- `vulnerability_class` = `injection`
- `cwe` containing `"CWE-78"` (OS command injection)
- `owasp` containing `"A03:2021"` (Injection)
- `file` = `command_injection.rb`
- A `description` that references command injection / shell metacharacters and the unescaped filename interpolation

The summary line should show at least `Critical: 1   High: 0   Medium: 0   Low: 0   Info: 0` (additional findings on the same fixture are tolerated; **missing the critical finding is a fail**).

**To get the same finding as raw JSON for scripting**, activate the skill with the `--json` argument.

## 3. Negative-control test (`phoenix_fragment_safe.ex`)

This fixture uses Ecto's positional-binding `fragment("? = ?", field, ^user_input)` form with the `^` pin — the SAFE form of an Ecto fragment. The Phoenix/Elixir framework pack's fragment-injection rule explicitly excludes this shape and must NOT fire.

**Procedure:**

1. Reset your test repository to a clean state (`git reset HEAD --` then `git checkout .`) so the diff only contains the negative-control fixture.
2. Stage the fixture (`git add phoenix_fragment_safe.ex`).
3. Activate the `security-review-essentials` skill with no arguments.
4. Wait for the review to complete and print its report.

**Expected outcome:**

Per `test/fixtures/EXPECTED.md`, the agent must produce **zero findings** on this fixture. The report should print either:

- `No findings. Reviewed 1 file.`

or:

- `Security review — 0 findings across 1 file`
  `Critical: 0   High: 0   Medium: 0   Low: 0   Info: 0`

Any finding on this fixture is a **false positive** and indicates a prompt regression in the Phoenix/Elixir rule pack — specifically, the rule pack's "do not flag positional-binding fragments with `^` pin" exclusion has not survived the port.

## 4. Result interpretation

Compare each fixture's output against `test/fixtures/EXPECTED.md`. The relevant lines are:

```
- [ ] `command_injection.rb` → injection (critical), `cwe: ["CWE-78"]`, `owasp: ["A03:2021"]` —
  HTTP-supplied `filename` interpolated unescaped into a shell command.
- [ ] `phoenix_fragment_safe.ex` → NONE — `fragment("? = ?", field, ^user_input)` positional-binding
  form with the `^` pin. The Phoenix Ecto fragment-injection rule must NOT fire here.
```

A passing smoke test means:

- The positive-control fixture produces a finding whose `vulnerability_class` matches `injection` and whose `severity` matches `critical`. CWE and OWASP arrays are advisory in `EXPECTED.md` (the eval runner emits `# warn:` TAP comments for mismatches but does not fail) — for the smoke test, treat them the same way: a missing or different CWE is a soft warning, not a hard failure.
- The negative-control fixture produces an empty `findings` array.

If both checks pass, the plugin is loaded, the agent prompt is intact, the skill's argument-parsing and dispatch logic work end-to-end, and the framework rule packs survived the port and reached the agent — the skill reads them from its own directory and sends them in the dispatch (README, *How the rules reach the agent*). Run the rule-file checks below as well: these two fixtures alone cannot tell a pack that arrived from core rules that happened to catch the same thing. Move on with confidence.

For a more thorough check against every fixture, run the eval suite with `bash scripts/run_eval.sh`, which dispatches this plugin's agent through Copilot CLI's programmatic mode. It has not yet been run against a real Copilot CLI; the README's *Running the eval locally* says what is unverified and how a run is recorded.

## 4b. Rule-file checks

The agent never reads a rule pack itself: the skill chooses the packs from the reviewed files, reads them from `skills/security-review-essentials/packs/` and sends each in the dispatch between `<<<STRIDE RULE FILE <name> <key>>>>` and `<<<END STRIDE RULE FILE <name> <key>>>>` lines, under a key it names on a `Rule-file key:` line. Nobody has yet seen this work in Copilot CLI, so check it by hand:

1. **A matching pack reaches the agent.** Stage `test/fixtures/phoenix_raw_xss.ex` in the test repository and activate the skill with no arguments. Expect the Phoenix finding from `EXPECTED.md` — `xss_or_code_exec` (high), `Phoenix.HTML.raw` on user-supplied `q` — and no `rule file not sent:` line. Ask Copilot CLI to show the dispatch prompt if it can, and confirm a `<<<STRIDE RULE FILE packs/phoenix.md <key>>>>` block, its key the one on the `Rule-file key:` line, sits after the mode tag and before the diff.
2. **A missing pack degrades to the core.** In a scratch copy of the plugin loaded with `copilot --plugin-dir <copy>`, make `skills/security-review-essentials/packs/phoenix.md` unreadable (`chmod 000`), and repeat step 1. Expect one `rule file not sent: packs/phoenix.md` line and a completed review on the core rules (a finding may or may not appear; an aborted review is the failure). Restore the mode afterwards.

Record what you saw, including whether the skill could resolve its own directory at all, in the CHANGELOG entry that ships the release.

## 5. Failure modes

If either check fails, look here first — these are the failure modes most likely to occur during a port, in roughly decreasing order of likelihood.

### Agent frontmatter

- **`tools:` field is missing or malformed.** The agent frontmatter must declare `tools: ["read", "search", "glob", "execute"]` (JSON array of lowercase strings); `bash scripts/check_agent_contract.sh` pins that line exactly. GitHub's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) gives `execute` as the shell tool (with `shell`, `Bash` and `powershell` as compatible names) and ignores tool names it does not recognize, so a wrong name does not stop the agent loading: it leaves the agent without that tool. A comma-separated string (the Claude Code shape) fails the same check.
- **`model: inherit` is still present.** That key is Claude-Code-specific and Copilot rejects unknown frontmatter keys. Strip it from `agents/security-reviewer.agent.md`.
- **Frontmatter `description:` still contains `<example>...</example>` blocks.** Those are Claude-Code-specific. Copilot expects a single concise paragraph. If the agent's `description` is too long, Copilot may truncate it in the agent picker.

### Rule files never reach the agent

- **The skill could not find its own directory, or Copilot CLI refused the read.** A `rule file not sent:` line for every pack, on every run, means the skill reads nothing from `skills/security-review-essentials/`. GitHub's [adding agent skills page](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) says the files in a skill's directory are made available alongside its instructions, but not how the model names that directory; this is the first thing to check on a new Copilot CLI release.
- **Every review is quiet on framework fixtures, with no `rule file not sent:` line.** The blocks were sent but voided: a marker line carrying the dispatch's key inside the reviewed content voids every block (the skill chose a key that content holds), and so does a block that is unclosed, sent twice, carries another key, names a file the agent's table does not list, or comes with no `Rule-file key:` line. A marker line without the key — reviewing this plugin's own rule files sends plenty — should change nothing.

### Skill tool-name mismatch

- **The skill's procedure references Claude-Code tool names.** `SKILL.md` body must use `read`, `search`, `glob`, `execute`, `skill` — never `Read`, `Grep`, `Glob`, `Bash`, `Agent`. Verify with:

  ```bash
  grep -E '\b(Read|Grep|Glob|Bash|Agent)\b' skills/security-review-essentials/SKILL.md
  ```

  The grep MUST return no matches (case-sensitive, word-boundary). Any hit indicates a missed rewrite.
- **`allowed-tools:` frontmatter survives.** That key is Claude-Code-specific. The skill frontmatter must contain only `name`, `description`, and (optionally) `skills_version`. Verify with `grep -E '^allowed-tools:' SKILL.md` returning no matches.

### Missing Copilot CLI flags

- **The skill drops or renames a flag.** Activating the skill with an unknown argument should produce a clear error. If `--full` does nothing, if `--json` outputs the human-readable report anyway, or if `--fail-on` is silently ignored, the argument-parsing step in `SKILL.md` Step 1 has been damaged. Cross-check against the README's argument table: every flag listed there must have a corresponding parse rule.

### Plugin manifest

- **`plugin.json` is at the wrong path.** Copilot expects it at the plugin root, NOT under `.claude-plugin/`. Verify `ls stride-copilot-security-review/plugin.json` succeeds and `ls stride-copilot-security-review/.claude-plugin/` fails.
- **`agents:` or `skills:` discovery keys are missing.** The manifest must declare `agents: "agents/"` and `skills: ["skills/"]` — without these, Copilot won't auto-discover the agent or the skill.
- **`hooks:` key is present pointing at a non-existent file.** This plugin ships no hooks. Adding the key without a corresponding `hooks/hooks.json` blocks plugin load.

### Fixture or `EXPECTED.md` drift

- **The fixture was modified.** The fixtures are intentionally vulnerable code; any edit invalidates the eval. Restore from this plugin's `test/fixtures/` directory with `git checkout` against a known-good commit.
- **`EXPECTED.md` was modified to match a wrong agent output.** That document is the spec, not a description of current behavior. If you find yourself wanting to edit `EXPECTED.md` to make the test pass, the agent prompt regressed — fix the prompt instead.

### Copilot CLI is not yet exercising batch mode

- **You see the plugin install but cannot activate the skill non-interactively.** The eval runner (`scripts/run_eval.sh`) now dispatches the agent through Copilot CLI's programmatic mode (`copilot -p … --agent security-reviewer --plugin-dir <repo root>`), but nobody has yet seen that select this plugin's agent — see the README's *Running the eval locally*. The reference CI workflow (`.github/workflows/security-review.yml`) still depends on the Claude Code CLI — see its `TODO(copilot-port)` header. The interactive smoke test described above DOES work in current Copilot CLI.

If none of the above match the symptom, capture the full skill output (or the raw JSON via `--json`) and open an issue at <https://github.com/cheezy/stride-copilot-security-review/issues> with the fixture name, the expected finding from `EXPECTED.md`, and the actual output.
