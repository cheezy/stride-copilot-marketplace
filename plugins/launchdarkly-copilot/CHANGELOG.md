# Changelog

All notable changes to the LaunchDarkly Copilot plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-04

Modernize the client-side SDK guidance to the scoped v4 packages and add
first-class browser and React scaffolding.

### Changed

- `launchdarkly-typescript-client` skill rewritten to teach the scoped v4
  packages (`@launchdarkly/js-client-sdk`, `@launchdarkly/react-sdk`) as the
  primary path — `createClient`/`client.start()`, the never-rejecting
  `waitForInitialization` status object, no-context typed variations,
  `createLDReactProvider`, and the typed hooks — with the unscoped v3 packages
  demoted to a labeled legacy section.
- `launchdarkly-java-sdk` TestData examples aligned on `booleanFlag()` and the
  Maven/Gradle SDK version pin made drift-resistant.
- `launchdarkly-reviewer` agent anti-pattern table expanded with the remaining
  skill-declared never-dos (per-request client, evaluate-before-init, SSR
  hydration, live-LD/real-key-in-tests, winner-differs-from-safe-default, and
  full-context/PII logging), v4-aware client detection, and a skill-to-reviewer
  parity note.
- README refreshed to the v4 packages and to the `stride-copilot-marketplace`
  vendored distribution; Supported SDKs, the skill index, the install path, and
  the status version updated.

### Added

- `launchdarkly-flag-scaffolding` gained first-class `browser` and `react`
  scaffold targets emitting the v4 client-side seam (client-side ID,
  `createClient`/`createLDReactProvider`) with both-states tests.
- `launchdarkly-flag-removal` Step 3 now classifies React hook call sites — a
  read behind a single custom hook collapses; a scattered hook read is reported
  for human follow-up, never auto-edited.
- `scripts/validate.mjs` — a dependency-free Node validation smoke script
  (version parity, skill/agent inventory, reference resolution, and a v3
  package-era drift guard).

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
