# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-07-20

### Changed

- **Renamed the plugin `stride-security-review-copilot` → `stride-copilot-security-review`** for naming consistency with the other `stride-copilot-*` Copilot ports. The GitHub repository was renamed (GitHub keeps an old→new redirect), and `plugin.json` (`name`, `homepage`, `repository`), `README.md`, and `docs/SMOKE_TEST.md` were updated to the new name. **Breaking for existing installs:** reinstall under the new name (`copilot plugin install https://github.com/cheezy/stride-copilot-security-review`); the old `stride-security-review-copilot` install identity no longer matches.

## [0.2.0] - 2026-07-04

### Fixed

- Vulnerability-class count reconciled to the authoritative 15-value enum (10 non-agentic + 5 agentic) across `SKILL.md` and this changelog; `supply_chain` is no longer dropped from the enumerated non-agentic lists.
- Corrected the stale "A fourth pack" wording in the `security-reviewer` agent prompt to "An eighth pack", consistent with the seven shipped framework rule packs.
- Reconciled the fixture count from a stale 61 to the actual 64 in the changelog and `docs/SMOKE_TEST.md`, and added a fixture/`EXPECTED.md` set-equality drift guard to `scripts/run_eval.sh` — it fails fast (exit 2) naming any file↔row divergence and runs under `--dry-run` (now a structural-only check that exits 0 over the 64-fixture suite).
- Resolved the self-contradictory `--rci` out-of-range handling with a single unambiguous clamp: a value `> 3` clamps to 3; `< 1`, non-integer, or bare `--rci` defaults to 1; an absent flag stays 0.
- Completed the skill's operational-rules flag inventory to include `--sarif`, `--base`, and `--fail-on` alongside the previously-listed seven flags.
- De-staled the SARIF `tool.driver.version` (was a pinned `2.1.0`; now tracks `plugin.json` and is documented as distinct from the SARIF format version `2.1.0`), repointed dangling `commands/security-review.md` references to `skills/security-review-essentials/SKILL.md`, removed the dead `commands/**` CI path filter, and updated `plugin.json`'s surface wording to name the `security-review-essentials` skill.

## [0.1.0] - 2026-05-21

### Added

- Initial Copilot CLI port from [stride-security-review 2.3.0](https://github.com/cheezy/stride-security-review).
- All seven framework rule packs carried over: Android/Kotlin, Django/Python, Express/Node.js, iOS/Swift, Phoenix/Elixir, Rails/Ruby, React/Next.js.
- Two scan modes carried over: diff (default) and `--full` (full-codebase scan with batched dispatch at 10 files per batch and a 256 KiB size cap).
- All advanced flags carried over: `--maestro` (MAESTRO 7-layer agentic-AI classification), `--rci [N]` (Recursive Criticism & Improvement passes, clamped to 3), `--baseline` and `--update-baseline` (acknowledged-finding suppression with stable SHA-256 fingerprints), `--patches` (surgical-fix unified diffs on findings where a minimal fix exists), `--sarif` (SARIF v2.1.0 emission for GitHub Code Scanning), `--fail-on <severity>` (CI threshold gating), `--base <ref>` (PR-against-base diff scoping).
- The `security-reviewer` agent prompt, vulnerability taxonomy (10 universal classes + 5 agentic classes), CWE/OWASP mapping, severity rubric, false-positive filter, and structured JSON output schema are byte-equivalent with the source plugin.
- Web defense-in-depth pack and multi-platform CI/CD pipeline pack (8 platforms) carried over.
- 64 fixture test cases and the TAP 13 eval runner carried over verbatim.

### Changed (vs. source plugin)

- Plugin surface changed from a Claude Code slash command (`/stride-security-review:security-review`) to a Copilot CLI skill (`security-review-essentials`). Activation is via the Copilot CLI's standard skill invocation; arguments are passed at activation time.
- Frontmatter and tool-name conventions adapted to Copilot CLI shape: agent `tools:` is now a JSON array of lowercase strings (`["read", "search", "glob", "run"]`); `model: inherit` and `allowed-tools:` keys removed; plugin manifest moved from `.claude-plugin/plugin.json` to root `plugin.json` with `agents:` and `skills:` discovery keys.
- The Claude Code slash-command pipeline (parse args → gather input → dispatch agent → render output) is now folded into the `security-review-essentials` skill body as a Procedure section.

### Known limitations (TODOs for the next release)

- The reference CI workflow (`.github/workflows/security-review.yml`) and the eval runner (`scripts/run_eval.sh`) currently install and invoke the Claude Code CLI; both files carry `TODO(copilot-port)` headers documenting the replacement targets for when Copilot CLI ships a settled non-interactive batch mode.
- The SARIF schema validator example in `schema/README.md` also references `claude -p` and is annotated with a `TODO(copilot-port)` for the same reason.

[0.3.0]: https://github.com/cheezy/stride-copilot-security-review/releases/tag/v0.3.0
[0.2.0]: https://github.com/cheezy/stride-copilot-security-review/releases/tag/v0.2.0
[0.1.0]: https://github.com/cheezy/stride-copilot-security-review/releases/tag/v0.1.0
