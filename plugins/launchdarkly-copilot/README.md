# LaunchDarkly Plugin for GitHub Copilot

A GitHub Copilot plugin that helps generate **correct, testable, and removable**
[LaunchDarkly](https://launchdarkly.com/) feature-flag code. A Copilot port of
the [launchdarkly](https://github.com/cheezy/launchdarkly) Claude Code plugin.

It encodes LaunchDarkly best practices so flag-gated code is:

- **Correct** — every evaluation passes a safe default; browser code uses a
  client-side ID, never a server SDK key.
- **Testable** — both the flag-on and flag-off branches are covered before a
  change is done.
- **Removable** — each flag is read at a single boundary behind a stable seam,
  so retiring it is a mechanical edit.

> **Status:** v0.2.0. Distributed via the vendored
> [stride-copilot-marketplace](https://github.com/cheezy/stride-copilot-marketplace)
> catalog and installable with the GitHub Copilot CLI (see [Installation](#installation)).

## Supported SDKs

- **Java** — server-side SDK (`com.launchdarkly:launchdarkly-java-server-sdk`).
- **TypeScript / Node** — server-side SDK (`@launchdarkly/node-server-sdk`).
- **TypeScript / browser** — v4 client-side JS SDK (`@launchdarkly/js-client-sdk`);
  the unscoped v3 `launchdarkly-js-client-sdk` is covered as a labeled legacy path.
- **React** — v4 React SDK (`@launchdarkly/react-sdk`); the unscoped v3
  `launchdarkly-react-client-sdk` is covered as a labeled legacy path.

## What's in this plugin

This is a GitHub Copilot plugin: a root `plugin.json` manifest with `skills`
under `skills/` and an agent under `agents/`. It ships **8 skills** and **1
agent** (Copilot has no slash-command surface, so the source plugin's two
commands are provided as skills).

### Skills

| Skill | What it covers |
|---|---|
| [`launchdarkly-fundamentals`](skills/launchdarkly-fundamentals/SKILL.md) | SDK-agnostic concepts: flags & variations, evaluation contexts, the safe default value, streaming vs polling & local evaluation, and the flag lifecycle with the design-for-removal principle. |
| [`launchdarkly-java-sdk`](skills/launchdarkly-java-sdk/SKILL.md) | Server-side Java SDK: one shared `LDClient` closed on shutdown, building an `LDContext`, defaulted variations, offline mode, and the `TestData` source. |
| [`launchdarkly-typescript-node`](skills/launchdarkly-typescript-node/SKILL.md) | Server-side Node SDK in TypeScript: `init` + `waitForInitialization`, typed defaulted variations, flush/close, and the `TestData` source. |
| [`launchdarkly-typescript-client`](skills/launchdarkly-typescript-client/SKILL.md) | Browser JS SDK + React SDK (v4): client-side-ID init via `createClient`/`client.start()` and `createLDReactProvider`, typed variation methods and hooks (`boolVariation`, `useBoolVariation`, `useInitializationStatus`, `useLDClient`), `identify`, bootstrapping, streaming, and SSR/hydration (v3 `LDProvider`/`useFlags` demoted to a labeled legacy section). |
| [`launchdarkly-flag-structure`](skills/launchdarkly-flag-structure/SKILL.md) | Structuring flag-gated code for cheap removal: single-boundary reads, a stable seam, named constants, a removal note, independently testable branches (Java + TS). |
| [`launchdarkly-testing`](skills/launchdarkly-testing/SKILL.md) | Testing **both** flag states deterministically with no network: Java/JUnit (parameterized + `@Nested`), TS Jest/Vitest (`it.each` + multiple `describe`), and React via `jest-launchdarkly-mock`. |
| [`launchdarkly-flag-scaffolding`](skills/launchdarkly-flag-scaffolding/SKILL.md) | Scaffold a removable, both-states-tested flag-gated code path in Java, TypeScript (Node), browser (v4 client-side JS), or React (v4) — a single-boundary seam, named constant + removal note, and a both-states test. |
| [`launchdarkly-flag-removal`](skills/launchdarkly-flag-removal/SKILL.md) | Safely retire a flag: collapse the seam to the chosen winning variation, remove the dead branch and branch-only tests, and report any usage it cannot safely collapse. |

### Agent

| Agent | What it does |
|---|---|
| [`launchdarkly-reviewer`](agents/launchdarkly-reviewer.agent.md) | Audits a diff or set of files for LaunchDarkly anti-patterns — missing default values, server SDK keys in browser code, scattered (non-single-boundary) reads, missing both-states tests, raw string-literal flag keys, and flags with no removal note — and returns findings grouped by severity. |

## Installation

This plugin is distributed via the vendored **stride-copilot-marketplace**
catalog. Register the marketplace and install the plugin with the GitHub Copilot
CLI:

```bash
copilot plugin marketplace add cheezy/stride-copilot-marketplace
copilot plugin install launchdarkly-copilot
```

Once installed, the skills activate when you work with LaunchDarkly code and the
review agent becomes available.

## Security

- Supply SDK keys via **environment variables or your config system**, never
  hardcoded literals, and never commit them (`.env` and `*.local` are
  gitignored).
- **Server SDK keys are secrets**; browser/React code must use the **client-side
  ID**. Never embed a server SDK key in a frontend bundle, and never gate
  secret-dependent logic purely on a client-side flag value (those values are
  visible to users).

## Validation

Run the dependency-free validation smoke script with plain Node (no
`npm install`, no third-party packages). It exits non-zero on any violation:

```bash
node scripts/validate.mjs
```

It checks:

- **Version parity** — `plugin.json` version equals the top `CHANGELOG.md`
  entry, the README **Status** line, and (when the vendored
  `stride-copilot-marketplace` repo is checked out beside this one, or pointed at
  by `STRIDE_COPILOT_MARKETPLACE`) that repo's `marketplace.json` plugin entry
  and README Plugins-table row.
- **Inventory** — every `skills/*/SKILL.md` has `name` + `description`
  frontmatter, the agent has a non-empty `tools:` list, and the README component
  index maps to the files on disk one-to-one (no unindexed or indexed-but-missing
  components).
- **References** — every namespaced `skills/…` / `agents/…` link in this README
  resolves to a real file.
- **v3 drift guard** — the legacy v3 package/API identifiers
  (`launchdarkly-js-client-sdk`, `launchdarkly-react-client-sdk`,
  `withLDProvider`, `asyncWithLDProvider`, `useFlags`, and a bare `initialize(`)
  appear **only** inside the labeled `## Legacy v3` section of the
  `launchdarkly-typescript-client` skill, never in its primary content.

### Follow-ups

- None outstanding for v0.2.0. The plugin is published through the
  **stride-copilot-marketplace** vendored catalog; keep its `marketplace.json`
  entry and Plugins-table row in sync with this plugin's `plugin.json` version on
  each release.

## License

[MIT](LICENSE) © Jeff Morgan
