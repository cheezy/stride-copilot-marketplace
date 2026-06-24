# Releasing / syncing the marketplace

This marketplace **vendors a pinned copy** of each plugin's tree under `plugins/<name>/`, and the catalog at [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) records each plugin's `version`. Because the plugin files live in this repo (not behind an external URL), a new upstream plugin release does **not** reach marketplace users until the vendored copy and the catalog version are re-synced here.

Run this process every time an upstream plugin (e.g. [`stride-copilot`](https://github.com/cheezy/stride-copilot)) cuts a new release.

## Two distinct versions

Keep these straight — they are not the same field:

- **Catalog version** — `metadata.version` in `marketplace.json`. Describes the marketplace catalog itself. Bump it only when the catalog structure changes, not on every plugin release.
- **Plugin entry version** — the `version` on each object in the `plugins[]` array. This **must equal the vendored plugin's own `plugin.json` version**. This is the field that goes stale on a plugin release.

The README [`Plugins` table](README.md#plugins) also lists each plugin's version for humans — keep it in sync with the plugin entry version too.

## Sync steps

Assume the upstream plugin has just tagged a new version (e.g. `stride-copilot` `vX.Y.Z`). From the repository root:

1. **Re-vendor the plugin tree**, excluding the source `.git` directory and any secret files:

   ```bash
   rsync -a --delete \
     --exclude='.git' \
     --exclude='.stride_auth.md' \
     --exclude='.env' \
     --exclude='*.local' \
     /path/to/stride-copilot/ plugins/stride-copilot/
   ```

   `--delete` ensures files removed upstream are also removed from the vendored copy. Never copy `.git`, `.stride_auth.md`, `.env`, or `*.local` — this repo is **public**.

2. **Bump the plugin entry version** in `.github/plugin/marketplace.json` so the `stride-copilot` entry's `version` matches the vendored `plugins/stride-copilot/plugin.json` version (`X.Y.Z`).

3. **Update the README `Plugins` table** version cell to the same `X.Y.Z`.

4. **Verify** the source path resolves and the versions match:

   ```bash
   node -e "const m=JSON.parse(require('fs').readFileSync('.github/plugin/marketplace.json')); const p=m.plugins.find(x=>x.name==='stride-copilot'); const v=JSON.parse(require('fs').readFileSync('plugins/stride-copilot/plugin.json')).version; require('fs').accessSync('plugins/stride-copilot/plugin.json'); if(p.version!==v) throw new Error('version mismatch: entry '+p.version+' != vendored '+v); console.log('synced at', v)"
   ```

5. **Scan for secrets**, then commit and push:

   ```bash
   git grep -nI 'BEGIN .*PRIVATE KEY\|ghp_\|github_pat_' $(git rev-list --all) | head   # expect empty
   git add -A
   git commit -m "Sync stride-copilot to X.Y.Z"
   git push origin main
   ```

## Checklist

- [ ] Vendored tree re-synced with `--delete`, no `.git` / secret files copied
- [ ] `marketplace.json` plugin entry `version` == vendored `plugin.json` version
- [ ] README `Plugins` table version updated to match
- [ ] Verify command prints `synced at X.Y.Z`
- [ ] Secret scan clean, committed and pushed

## Adding a new plugin

The **Sync steps** above re-version a plugin that is *already* in the catalog. Adding a **new** plugin is a different flow: you create a fresh vendored copy and a new `plugins[]` entry, and — because the catalog's content changes — you bump `metadata.version`. Use this when registering a plugin for the first time (e.g. how `stride-copilot-ideation` was added alongside `stride-copilot`).

Assume the new plugin `<name>` has a tagged release `vX.Y.Z`. From the repository root:

1. **Vendor the new plugin tree** into a fresh `plugins/<name>/`, excluding `.git`, the gitignored `.stride/` runtime dir, and any secret files:

   ```bash
   rsync -a --delete \
     --exclude='.git' \
     --exclude='.stride' \
     --exclude='.stride_auth.md' \
     --exclude='.env' \
     --exclude='.env.local' \
     --exclude='*.local' \
     --exclude='.stride-env-cache' \
     --exclude='.stride-changed-files.json' \
     /path/to/<name>/ plugins/<name>/
   ```

   Never copy `.git`, the `.stride/` runtime dir, or any secret file — this repo is **public**.

2. **Add a new `plugins[]` entry** to `.github/plugin/marketplace.json` with `name`, a concise one-line `description`, `version` (`X.Y.Z`, equal to the vendored `plugin.json` version), and `source` (`./plugins/<name>`). Leave the existing entries untouched.

3. **Bump `metadata.version`** (a minor bump) — adding a plugin changes the catalog content. This is the key difference from a version sync, which leaves `metadata.version` alone.

4. **Add a README `Plugins` table row** for the new plugin, matching the entry's version and description.

5. **Verify** every entry's `version` equals its vendored `plugin.json` version and every `source` resolves:

   ```bash
   node -e "const m=JSON.parse(require('fs').readFileSync('.github/plugin/marketplace.json')); m.plugins.forEach(p=>{const v=JSON.parse(require('fs').readFileSync(p.source.replace(/^\.\//,'')+'/plugin.json')).version; if(p.version!==v) throw new Error(p.name+' entry '+p.version+' != vendored '+v); require('fs').accessSync(p.source.replace(/^\.\//,'')+'/plugin.json')}); console.log('all '+m.plugins.length+' plugins resolve and versions match')"
   ```

6. **Scan for secrets**, then commit and push:

   ```bash
   git grep -nI 'BEGIN .*PRIVATE KEY\|ghp_\|github_pat_' $(git rev-list --all) | head   # expect empty
   git add -A
   git commit -m "Add <name> as a marketplace plugin"
   git push origin main
   ```

### Add-a-plugin checklist

- [ ] New plugin vendored into `plugins/<name>/`, no `.git` / `.stride` / secret files copied
- [ ] New `plugins[]` entry added (existing entries untouched), entry `version` == vendored `plugin.json` version
- [ ] `metadata.version` bumped (minor)
- [ ] README `Plugins` table row added
- [ ] Verify command prints `all N plugins resolve and versions match`
- [ ] Secret scan clean, committed and pushed
