# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-21

### Added

- Initial Copilot CLI port from [stride-security-review 2.3.0](https://github.com/cheezy/stride-security-review).
- All seven framework rule packs carried over: Android/Kotlin, Django/Python, Express/Node.js, iOS/Swift, Phoenix/Elixir, Rails/Ruby, React/Next.js.
- Two scan modes carried over: diff (default) and `--full` (full-codebase scan with batched dispatch at 10 files per batch and a 256 KiB size cap).
- All advanced flags carried over: `--maestro` (MAESTRO 7-layer agentic-AI classification), `--rci [N]` (Recursive Criticism & Improvement passes, clamped to 3), `--baseline` and `--update-baseline` (acknowledged-finding suppression with stable SHA-256 fingerprints), `--patches` (surgical-fix unified diffs on findings where a minimal fix exists), `--sarif` (SARIF v2.1.0 emission for GitHub Code Scanning), `--fail-on <severity>` (CI threshold gating), `--base <ref>` (PR-against-base diff scoping).
- The `security-reviewer` agent prompt, vulnerability taxonomy (9 universal classes + 5 agentic classes), CWE/OWASP mapping, severity rubric, false-positive filter, and structured JSON output schema are byte-equivalent with the source plugin.
- Web defense-in-depth pack and multi-platform CI/CD pipeline pack (8 platforms) carried over.
- 61 fixture test cases and the TAP 13 eval runner carried over verbatim.

### Changed (vs. source plugin)

- Plugin surface changed from a Claude Code slash command (`/stride-security-review:security-review`) to a Copilot CLI skill (`security-review-essentials`). Activation is via the Copilot CLI's standard skill invocation; arguments are passed at activation time.
- Frontmatter and tool-name conventions adapted to Copilot CLI shape: agent `tools:` is now a JSON array of lowercase strings (`["read", "search", "glob", "run"]`); `model: inherit` and `allowed-tools:` keys removed; plugin manifest moved from `.claude-plugin/plugin.json` to root `plugin.json` with `agents:` and `skills:` discovery keys.
- The Claude Code slash-command pipeline (parse args → gather input → dispatch agent → render output) is now folded into the `security-review-essentials` skill body as a Procedure section.

### Known limitations (TODOs for the next release)

- The reference CI workflow (`.github/workflows/security-review.yml`) and the eval runner (`scripts/run_eval.sh`) currently install and invoke the Claude Code CLI; both files carry `TODO(copilot-port)` headers documenting the replacement targets for when Copilot CLI ships a settled non-interactive batch mode.
- The SARIF schema validator example in `schema/README.md` also references `claude -p` and is annotated with a `TODO(copilot-port)` for the same reason.

[0.1.0]: https://github.com/cheezy/stride-security-review-copilot/releases/tag/v0.1.0
