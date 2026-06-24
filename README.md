# Stride Copilot Marketplace

Marketplace catalog for [Stride](https://www.stridelikeaboss.com) GitHub Copilot CLI plugins — a task management platform designed for AI agents.

This repository hosts the [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) catalog that registers Stride's GitHub Copilot plugins so they can be discovered and installed via the Copilot CLI. Each plugin's files live **in this repository** (under `plugins/<name>/`), and the catalog's `source` field points at that in-repo path.

## Adding the marketplace

Register this marketplace with the Copilot CLI using its `owner/repo` shorthand:

```bash
copilot plugin marketplace add cheezy/stride-copilot-marketplace
```

Then install a plugin from the catalog by name:

```bash
copilot plugin install stride-copilot
```

### Managing the marketplace and plugins

```bash
copilot plugin marketplace list                 # View registered marketplaces
copilot plugin list                             # View installed plugins
copilot plugin update stride-copilot            # Update a plugin to the latest version
copilot plugin uninstall stride-copilot         # Remove a plugin
```

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [`stride-copilot`](plugins/stride-copilot) | 2.20.0 | Task lifecycle skills and custom agents for Stride kanban: claiming, completing, and creating tasks and goals for AI agents in GitHub Copilot CLI. |
| [`stride-copilot-ideation`](plugins/stride-copilot-ideation) | 0.2.0 | Turn an idea into shipped Stride tasks from GitHub Copilot CLI: an interactive ideation session that produces a committed requirements doc, plus a stridify step that decomposes it into a Stride batch and posts it to the API. |
| [`stride-security-review-copilot`](plugins/stride-security-review-copilot) | 0.1.0 | AI-powered security review for code changes via the `/stride-security-review:security-review` slash command: multi-language semantic vulnerability detection with SARIF output and CI severity gating. |

The plugin list above is kept in sync with the `plugins[]` array in [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json).

## How the catalog works

The catalog lives at [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) and has this shape:

- **`name`** — the marketplace identifier (`stride-copilot-marketplace`).
- **`owner`** — `{ name, email }` of the maintainer.
- **`metadata`** — `{ description, version }` for the catalog itself.
- **`plugins[]`** — one entry per plugin, each with `name`, `description`, `version`, and `source`.

Every plugin `source` is an **in-repo relative path** (e.g. `./plugins/stride-copilot`) resolved from the repository root, so the plugin's files are vendored into this repo rather than referenced by an external URL. Keep each entry's `version` in sync with the vendored plugin's `plugin.json` version.

## Maintenance

Each plugin's files are vendored into this repo as a pinned copy, so a new upstream plugin release must be re-synced here before marketplace users receive it. See [RELEASE.md](RELEASE.md) for the step-by-step process — re-vendor `plugins/<name>/` (excluding `.git` and secrets), bump the `marketplace.json` plugin entry version to match the vendored `plugin.json`, update the `Plugins` table, verify, and push.

## License

[MIT](LICENSE) © 2026 Jeff Morgan
