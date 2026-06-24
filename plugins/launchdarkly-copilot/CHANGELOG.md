# Changelog

All notable changes to the LaunchDarkly Copilot plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial release of the GitHub Copilot port of the LaunchDarkly plugin.

### Added

- Repository scaffold: root `plugin.json` (Copilot manifest with `agents`/`skills`
  keys), `skills/` and `agents/` directories, README, LICENSE, and `.gitignore`.
- **Skills (8):**
  - `launchdarkly-fundamentals` — SDK-agnostic concepts and the flag lifecycle.
  - `launchdarkly-java-sdk` — server-side Java SDK usage.
  - `launchdarkly-typescript-node` — server-side Node SDK usage in TypeScript.
  - `launchdarkly-typescript-client` — browser JS SDK and React SDK usage.
  - `launchdarkly-flag-structure` — structuring flag-gated code for cheap removal.
  - `launchdarkly-testing` — testing both flag states deterministically.
  - `launchdarkly-flag-scaffolding` — scaffold a removable, both-states-tested
    flag-gated code path (ported from the Claude Code `/ld-scaffold` command).
  - `launchdarkly-flag-removal` — safely retire a flag by collapsing to the
    winning variation (ported from the Claude Code `/ld-remove-flag` command).
- **Agent (1):**
  - `launchdarkly-reviewer` — audits a diff or files for LaunchDarkly
    anti-patterns, grouped by severity (Copilot `.agent.md` format).
- Full README with a component index, supported-SDK list, install notes, and a
  security section.
