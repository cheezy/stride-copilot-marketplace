# Changelog

All notable changes to the `stride-copilot-exploratory-testing` plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-21

Initial release: the complete GitHub Copilot CLI port of `cheezy/stride-exploratory-testing`.

### Added

- **Repository and manifest.** Standalone git repository with a root-level `plugin.json` (Copilot schema: root manifest plus `"agents": "agents/"` and `"skills": ["skills/"]`), `README.md`, `HEURISTICS.md`, `LICENSE` (MIT), and this changelog. There is intentionally **no** `commands/` directory — Copilot CLI has no slash commands.
- **Core knowledge skills.** `stride-exploratory-testing` (orchestrator front door), `chartering`, `heuristics`, `oracles`, and `session` — the exploratory-testing doctrine.
- **Command-derived skills.** `stride-exploratory-testing-charter`, `-nightmare-headline`, `-explore`, `-recon`, and `-debrief` — the five upstream slash commands ported as named Copilot skills (Activation-section frontmatter, no `allowed-tools`/`argument-hint`).
- **Agents.** `agents/charter-generator.agent.md` and `agents/explorer.agent.md` (Copilot `.agent.md` format, array-form read-only/`run` tools, no `model` field).
- **Fixtures.** Worked `example-charters.md`, `example-session-sheet.md`, and `example-debrief.md` (synthetic *ExpenseFlow* target) that double as templates and smoke-test regression anchors.
- **Smoke tests.** Cross-platform `lib/test-structure.{sh,ps1}`, `lib/test-frontmatter.{sh,ps1}`, and `lib/test-all.{sh,ps1}` — offline structure/frontmatter validation that gates a release (no network, no `jq`).

### Distribution

- **Vendored into `stride-copilot-marketplace`.** Registered in the existing `cheezy/stride-copilot-marketplace` catalog at `0.1.0` — the plugin tree is vendored under `plugins/stride-copilot-exploratory-testing/` with a matching `plugins[]` entry (`source: ./plugins/stride-copilot-exploratory-testing`), and the catalog `metadata.version` was bumped to `1.6.0`. Once the catalog is registered, install by name with `copilot plugin install stride-copilot-exploratory-testing` (or directly with `copilot plugin install https://github.com/cheezy/stride-copilot-exploratory-testing`; see the README).
