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
