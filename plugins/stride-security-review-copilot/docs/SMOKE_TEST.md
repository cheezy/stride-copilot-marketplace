# Smoke Test — stride-security-review-copilot

This document describes the manual end-to-end verification procedure for the ported plugin. Run it after each change to the agent prompt, the `security-review-essentials` skill, or the plugin manifest, and before publishing a new release.

The smoke test exercises **two fixtures**: one that MUST produce a finding (positive control) and one that MUST NOT (negative control). Together they confirm that the agent fires when it should and stays quiet when it should — the minimum signal that the plugin is loaded correctly and the agent prompt has not regressed.

> This document is a procedure, not a passed test. The Copilot CLI smoke test must be run by a human in a real Copilot CLI session — it has not been exercised from within an automated workflow.

## 1. Prerequisites

- **Copilot CLI** installed and on `$PATH`. Verify with `copilot --version`.
- **A test repository** initialized with `git init` somewhere on your filesystem. The skill scopes its review by `git diff HEAD` or `git ls-files`, so the procedure needs an actual git working tree to run against.
- **The plugin installed locally.** From the repository root of this plugin checkout (`stride-security-review-copilot/`), run:

  ```bash
  copilot plugin install .
  ```

  (Alternatively, install from the remote: `copilot plugin install https://github.com/cheezy/stride-security-review-copilot`.)

  Verify with `copilot plugin list` — `stride-security-review-copilot` should appear with the version from `plugin.json` (currently `0.1.0`).

- **The fixture files copied into your test repository.** The positive- and negative-control fixtures live in this plugin's `test/fixtures/` directory; copy them into your test repository's working tree before running the procedure:

  ```bash
  cp /path/to/stride-security-review-copilot/test/fixtures/command_injection.rb     ./
  cp /path/to/stride-security-review-copilot/test/fixtures/phoenix_fragment_safe.ex ./
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

If both checks pass, the plugin is loaded, the agent prompt is intact, the skill's argument-parsing and dispatch logic work end-to-end, and the framework rule packs survived the port. Move on with confidence.

For a more thorough check against all 64 fixtures, run the eval suite from `scripts/run_eval.sh` once the Copilot CLI batch-mode replacement lands (see the TODO header in that file).

## 5. Failure modes

If either check fails, look here first — these are the failure modes most likely to occur during a port, in roughly decreasing order of likelihood.

### Agent frontmatter

- **`tools:` field is missing or malformed.** The agent frontmatter must declare `tools: ["read", "search", "glob", "run"]` (JSON array of lowercase strings). If it's a comma-separated string (the Claude Code shape) or includes Claude-Code-only names like `Read`, `Grep`, `Glob`, `Bash`, `Agent`, Copilot CLI will refuse to load the agent.
- **`model: inherit` is still present.** That key is Claude-Code-specific and Copilot rejects unknown frontmatter keys. Strip it from `agents/security-reviewer.agent.md`.
- **Frontmatter `description:` still contains `<example>...</example>` blocks.** Those are Claude-Code-specific. Copilot expects a single concise paragraph. If the agent's `description` is too long, Copilot may truncate it in the agent picker.

### Skill tool-name mismatch

- **The skill's procedure references Claude-Code tool names.** `SKILL.md` body must use `read`, `search`, `glob`, `run`, `skill` — never `Read`, `Grep`, `Glob`, `Bash`, `Agent`. Verify with:

  ```bash
  grep -E '\b(Read|Grep|Glob|Bash|Agent)\b' skills/security-review-essentials/SKILL.md
  ```

  The grep MUST return no matches (case-sensitive, word-boundary). Any hit indicates a missed rewrite.
- **`allowed-tools:` frontmatter survives.** That key is Claude-Code-specific. The skill frontmatter must contain only `name`, `description`, and (optionally) `skills_version`. Verify with `grep -E '^allowed-tools:' SKILL.md` returning no matches.

### Missing Copilot CLI flags

- **The skill drops or renames a flag.** Activating the skill with an unknown argument should produce a clear error. If `--full` does nothing, if `--json` outputs the human-readable report anyway, or if `--fail-on` is silently ignored, the argument-parsing step in `SKILL.md` Step 1 has been damaged. Cross-check against the README's argument table: every flag listed there must have a corresponding parse rule.

### Plugin manifest

- **`plugin.json` is at the wrong path.** Copilot expects it at the plugin root, NOT under `.claude-plugin/`. Verify `ls stride-security-review-copilot/plugin.json` succeeds and `ls stride-security-review-copilot/.claude-plugin/` fails.
- **`agents:` or `skills:` discovery keys are missing.** The manifest must declare `agents: "agents/"` and `skills: ["skills/"]` — without these, Copilot won't auto-discover the agent or the skill.
- **`hooks:` key is present pointing at a non-existent file.** This plugin ships no hooks. Adding the key without a corresponding `hooks/hooks.json` blocks plugin load.

### Fixture or `EXPECTED.md` drift

- **The fixture was modified.** The fixtures are intentionally vulnerable code; any edit invalidates the eval. Restore from this plugin's `test/fixtures/` directory with `git checkout` against a known-good commit.
- **`EXPECTED.md` was modified to match a wrong agent output.** That document is the spec, not a description of current behavior. If you find yourself wanting to edit `EXPECTED.md` to make the test pass, the agent prompt regressed — fix the prompt instead.

### Copilot CLI is not yet exercising batch mode

- **You see the plugin install but cannot activate the skill non-interactively.** Until Copilot CLI ships a settled non-interactive batch mode, the eval runner (`scripts/run_eval.sh`) and the reference CI workflow (`.github/workflows/security-review.yml`) still depend on the Claude Code CLI — see their `TODO(copilot-port)` headers. The interactive smoke test described above DOES work in current Copilot CLI; it's the automation around it that's waiting on the batch-mode landing.

If none of the above match the symptom, capture the full skill output (or the raw JSON via `--json`) and open an issue at <https://github.com/cheezy/stride-security-review-copilot/issues> with the fixture name, the expected finding from `EXPECTED.md`, and the actual output.
