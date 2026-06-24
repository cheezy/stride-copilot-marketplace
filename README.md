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
| [`stride-copilot`](plugins/stride-copilot) | 2.19.0 | Task lifecycle skills and custom agents for Stride kanban: claiming, completing, and creating tasks and goals for AI agents in GitHub Copilot CLI. |

The plugin list above is kept in sync with the `plugins[]` array in [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json).

## How the catalog works

The catalog lives at [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) and has this shape:

- **`name`** — the marketplace identifier (`stride-copilot-marketplace`).
- **`owner`** — `{ name, email }` of the maintainer.
- **`metadata`** — `{ description, version }` for the catalog itself.
- **`plugins[]`** — one entry per plugin, each with `name`, `description`, `version`, and `source`.

Every plugin `source` is an **in-repo relative path** (e.g. `./plugins/stride-copilot`) resolved from the repository root, so the plugin's files are vendored into this repo rather than referenced by an external URL. Keep each entry's `version` in sync with the vendored plugin's `plugin.json` version.

## License

[MIT](LICENSE) © 2026 Jeff Morgan
