# Releasing / syncing the marketplace

This marketplace **vendors a pinned copy** of each plugin's tree under `plugins/<name>/`, and the catalog at [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) records each plugin's `version`. Because the plugin files live in this repo (not behind an external URL), a new upstream plugin release does **not** reach marketplace users until the vendored copy and the catalog version are re-synced here.

Run this process every time an upstream plugin (e.g. [`stride-copilot`](https://github.com/cheezy/stride-copilot)) cuts a new release.

## Three version numbers to keep straight

These are three independent things — do not sync one to another:

- **Catalog version** — `metadata.version` in `marketplace.json`. Describes the marketplace catalog itself. Bump it only when the catalog structure changes — in practice, only when a plugin is **added** (see [Adding a new plugin](#adding-a-new-plugin)) — not on every plugin release.
- **Plugin entry version** — the `version` on each object in the `plugins[]` array. This **must equal the vendored plugin's own `plugin.json` version**. This is the field that goes stale on a plugin release.
- **Catalog tag series** — this repository's own `git` tags (`v2.35.0` and counting). This series is **independent of the catalog version and of every plugin version**: it advances by one minor bump per release of *this repo*, whether that release was a plugin sync or a new plugin. It is **not** derived from `metadata.version` (which sits far behind, and only moves when a plugin is added) and **not** derived from the plugin's `X.Y.Z`. Never reuse a plugin's version as the catalog tag — the two series collide in shape, and a plugin tag and a catalog tag with the same name point at unrelated trees. Take the next free number in this repo's own series:

  ```bash
  git tag --list --sort=-v:refname | head -1   # highest existing catalog tag
  ```

The README [`Plugins` table](README.md#plugins) also lists each plugin's version for humans — keep it in sync with the plugin entry version too.

## Sync steps

Assume the upstream plugin has just tagged a new version (e.g. `stride-copilot` `vX.Y.Z`). From the repository root:

1. **Re-vendor the plugin tree**, excluding the source `.git` directory and any secret files:

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
     /path/to/stride-copilot/ plugins/stride-copilot/
   ```

   `--delete` ensures files removed upstream are also removed from the vendored copy. Never copy `.git`, the `.stride/` runtime dir, `.stride_auth.md`, `.env*`, `*.local`, or the `.stride-env-cache` / `.stride-changed-files.json` runtime artifacts — this repo is **public**.

   This exclude list is **identical to the one in [Adding a new plugin](#adding-a-new-plugin)** below, and to the `stride-codex-marketplace` `RELEASE.md`. Keep all three in lockstep: the plugin repo you rsync *from* sits beside a real `.stride_auth.md`, so this list is the primary containment. Do not rely on the vendored copy's own `.gitignore` catching a stray — that is luck, not design.

2. **Bump the plugin entry version** in `.github/plugin/marketplace.json` so the `stride-copilot` entry's `version` matches the vendored `plugins/stride-copilot/plugin.json` version (`X.Y.Z`).

3. **Update the README `Plugins` table** version cell to the same `X.Y.Z`.

4. **Verify** the source path resolves and the versions match:

   ```bash
   node -e "const m=JSON.parse(require('fs').readFileSync('.github/plugin/marketplace.json')); const p=m.plugins.find(x=>x.name==='stride-copilot'); const v=JSON.parse(require('fs').readFileSync('plugins/stride-copilot/plugin.json')).version; require('fs').accessSync('plugins/stride-copilot/plugin.json'); if(p.version!==v) throw new Error('version mismatch: entry '+p.version+' != vendored '+v); console.log('synced at', v)"
   ```

5. **Scan for secrets**, then commit and push:

   ```bash
   git grep -nI 'BEGIN [A-Z ]*PRIVATE KEY\|ghp_[A-Za-z0-9]\{20,\}\|github_pat_[A-Za-z0-9_]\{20,\}\|stride_dev_[A-Za-z0-9+/=]\{30,\}\|stride_prod_[A-Za-z0-9+/=]\{30,\}' $(git rev-list --all)   # expect empty
   git add -A
   git commit -m "Sync stride-copilot to X.Y.Z"
   git push origin main
   ```

   **Expect literally zero output.** Any hit is a real finding — investigate before pushing. See [About the secret-scan pattern](#about-the-secret-scan-pattern) for why each clause is shaped the way it is; do not simplify it without re-reading that section.

6. **Tag the catalog** with the next free number in *this repo's* tag series — **not** the plugin's `X.Y.Z`, and **not** `metadata.version` (see [Three version numbers to keep straight](#three-version-numbers-to-keep-straight)). Writing `vA.B.C` for that catalog tag:

   ```bash
   git tag --list --sort=-v:refname | head -1   # highest existing catalog tag
   git tag vA.B.C
   git push origin vA.B.C
   ```

7. **Cut the GitHub release** for that tag:

   ```bash
   gh release create vA.B.C --title "vA.B.C" --notes "Sync stride-copilot to X.Y.Z"
   ```

   The tag is `vA.B.C` (this repo's series); the plugin version `X.Y.Z` belongs in the notes, describing *what* the release syncs.

   **Publishing a release requires the user's explicit authorization in that turn.** It creates a public artifact on a public repository, and authorization to perform the sync — or to run any earlier step here — does not carry over to this one. If you have not been told to release in the current turn, stop after step 6 and ask.

   A sync that stops before these two steps leaves the catalog pushed but unreleased. That is the gap this section exists to close, so treat steps 6 and 7 as part of the release, not as optional follow-up.

## Checklist

- [ ] Vendored tree re-synced with `--delete`, no `.git` / secret files copied
- [ ] `marketplace.json` plugin entry `version` == vendored `plugin.json` version
- [ ] README `Plugins` table version updated to match
- [ ] Verify command prints `synced at X.Y.Z`
- [ ] Secret scan returns zero output, committed and pushed
- [ ] Catalog tagged `vA.B.C` — next free number in this repo's series, not the plugin's `X.Y.Z` — and the tag pushed
- [ ] GitHub release cut for `vA.B.C`, with the user's explicit authorization in that turn

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
   git grep -nI 'BEGIN [A-Z ]*PRIVATE KEY\|ghp_[A-Za-z0-9]\{20,\}\|github_pat_[A-Za-z0-9_]\{20,\}\|stride_dev_[A-Za-z0-9+/=]\{30,\}\|stride_prod_[A-Za-z0-9+/=]\{30,\}' $(git rev-list --all)   # expect empty
   git add -A
   git commit -m "Add <name> as a marketplace plugin"
   git push origin main
   ```

   **Expect literally zero output.** Any hit is a real finding — investigate before pushing. This is the same pattern as the [Sync steps](#sync-steps); keep the two identical. See [About the secret-scan pattern](#about-the-secret-scan-pattern).

### Add-a-plugin checklist

- [ ] New plugin vendored into `plugins/<name>/`, no `.git` / `.stride` / secret files copied
- [ ] New `plugins[]` entry added (existing entries untouched), entry `version` == vendored `plugin.json` version
- [ ] `metadata.version` bumped (minor)
- [ ] README `Plugins` table row added
- [ ] Verify command prints `all N plugins resolve and versions match`
- [ ] Secret scan returns zero output, committed and pushed

## About the secret-scan pattern

The scan in both flows above is one pattern; keep them identical. Each clause is shaped deliberately, and simplifying any of them reintroduces a bug this repo has already had.

| Clause | Why it is shaped this way |
|---|---|
| `stride_dev_[A-Za-z0-9+/=]\{30,\}` | **This repo's own product tokens.** A real Stride bearer token is **always exactly 43** characters after the prefix — the generator is `:crypto.strong_rand_bytes(32) \|> Base.encode64(padding: false)`, so the length is fixed, and `Base.encode64` (not `url_encode64`) emits the `A-Za-z0-9+/` alphabet, never a run-breaking `_` or `-`. The vendored plugins carry ~12 synthetic fixtures (`stride_dev_PRODUCTIONTOKEN`, `stride_dev_TEST_TOKEN_FOR_SMOKE_TEST_ONLY`, `stride_dev_your_token_here`, …) whose longest unbroken run is **15** characters — every one is either short or broken by an `_`. The `{30,}` bound sits between 15 and 43, so it catches every real token and reports none of the fixtures. A bare `stride_dev_` clause would fire on all 12, and a scan that is always red is a scan everyone learns to ignore. |
| `stride_prod_[A-Za-z0-9+/=]\{30,\}` | Same reasoning for production tokens. |
| `BEGIN [A-Z ]*PRIVATE KEY` | Matches `BEGIN RSA/EC/OPENSSH/… PRIVATE KEY`. It is **not** `BEGIN .*PRIVATE KEY`, because `.*` matches the literal `.*` in this file — the old pattern reported *this document* as a leak on every run, forever, via `git rev-list --all`. `[A-Z ]*` cannot match `.` or `*`, so the pattern no longer finds itself. |
| `ghp_[A-Za-z0-9]\{20,\}` / `github_pat_[A-Za-z0-9_]\{20,\}` | Real GitHub tokens, not the bare prefixes. The bare form matched this file's own prose and the pattern text itself. |

Two consequences worth keeping:

- **Zero output is the pass condition.** There is no `| head` and no `grep -v` allow-list, because the pattern excludes fixtures and self-matches structurally rather than filtering them after the fact. An allow-list rots as fixtures are added; a shape-based bound does not.
- **The scan covers all history** (`$(git rev-list --all)`), so a token committed and later removed is still caught. That is also why a self-matching pattern is unacceptable: it would be permanently red.

To re-validate after editing the pattern: plant a realistic 43-character fake token in a scratch file, confirm the scan reports it, delete it, and confirm the scan then returns nothing across all history.
