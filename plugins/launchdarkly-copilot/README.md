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

> **Status:** v0.1.0. Built and used locally / from GitHub — not published to a
> marketplace.

## Supported SDKs

- **Java** — server-side SDK (`com.launchdarkly:launchdarkly-java-server-sdk`).
- **TypeScript / Node** — server-side SDK (`@launchdarkly/node-server-sdk`).
- **TypeScript / browser** — client-side JS SDK (`launchdarkly-js-client-sdk`).
- **React** — React SDK (`launchdarkly-react-client-sdk`).

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
| [`launchdarkly-typescript-client`](skills/launchdarkly-typescript-client/SKILL.md) | Browser JS SDK + React SDK: client-side-ID init, `identify`, bootstrapping, streaming, `LDProvider`/`useFlags`/`useLDClient`, and SSR/hydration. |
| [`launchdarkly-flag-structure`](skills/launchdarkly-flag-structure/SKILL.md) | Structuring flag-gated code for cheap removal: single-boundary reads, a stable seam, named constants, a removal note, independently testable branches (Java + TS). |
| [`launchdarkly-testing`](skills/launchdarkly-testing/SKILL.md) | Testing **both** flag states deterministically with no network: Java/JUnit (parameterized + `@Nested`), TS Jest/Vitest (`it.each` + multiple `describe`), and React via `jest-launchdarkly-mock`. |
| [`launchdarkly-flag-scaffolding`](skills/launchdarkly-flag-scaffolding/SKILL.md) | Scaffold a removable, both-states-tested flag-gated code path in Java or TypeScript (a single-boundary seam, named constant + removal note, and a TestData both-states test). |
| [`launchdarkly-flag-removal`](skills/launchdarkly-flag-removal/SKILL.md) | Safely retire a flag: collapse the seam to the chosen winning variation, remove the dead branch and branch-only tests, and report any usage it cannot safely collapse. |

### Agent

| Agent | What it does |
|---|---|
| [`launchdarkly-reviewer`](agents/launchdarkly-reviewer.agent.md) | Audits a diff or set of files for LaunchDarkly anti-patterns — missing default values, server SDK keys in browser code, scattered (non-single-boundary) reads, missing both-states tests, raw string-literal flag keys, and flags with no removal note — and returns findings grouped by severity. |

## Installation

This is a standalone GitHub Copilot plugin (not published to a marketplace).
Install it from its GitHub repository / local path with the GitHub Copilot CLI
(`copilot plugin --help` for the exact subcommands in your version). Once
installed, the skills activate when you work with LaunchDarkly code and the
review agent becomes available.

## Security

- Supply SDK keys via **environment variables or your config system**, never
  hardcoded literals, and never commit them (`.env` and `*.local` are
  gitignored).
- **Server SDK keys are secrets**; browser/React code must use the **client-side
  ID**. Never embed a server SDK key in a frontend bundle, and never gate
  secret-dependent logic purely on a client-side flag value (those values are
  visible to users).

## Local-load validation

For v0.1.0 the layout was validated against the on-disk component set:

- Root `plugin.json` is valid JSON (v0.1.0) with the `agents`/`skills` keys.
- All **8 skills** have valid `name`/`description` frontmatter and are indexed
  above.
- The **agent** (`launchdarkly-reviewer.agent.md`) has valid frontmatter (a
  `tools:` list) and is indexed above.

The README component index matches the files on disk one-to-one; there are no
unindexed components and no indexed-but-missing components.

### Follow-ups

- None outstanding for v0.1.0. A marketplace listing is intentionally out of
  scope for this release.

## License

[MIT](LICENSE) © Jeff Morgan
