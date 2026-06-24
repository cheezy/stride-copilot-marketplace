# Stride Copilot Marketplace

Marketplace catalog for [Stride](https://www.stridelikeaboss.com) GitHub Copilot CLI plugins — a task management platform designed for AI agents.

This repository hosts the `.github/plugin/marketplace.json` catalog that registers Stride's GitHub Copilot plugins so they can be discovered and installed via the Copilot CLI.

## Usage

Add this marketplace to the Copilot CLI:

```bash
copilot plugin marketplace add https://github.com/cheezy/stride-copilot-marketplace
```

Then install a plugin from the catalog:

```bash
copilot plugin install <plugin-name>
```

## Catalog

The catalog lives at [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json). Each entry registers a plugin with its name, source URL, description, and version. Plugins will be added in subsequent releases.
