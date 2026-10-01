# Releasing Stride Copilot Lite

A release here is a manifest bump, a stamped changelog heading, a tag and a
GitHub release — and then a sync of `stride-copilot-marketplace`, which carries
a vendored copy of this tree under `plugins/stride-copilot-lite/`. This file
writes versions as `X.Y.Z`; it names no real one.

## The three facts

**Where the version lives.** The root `plugin.json` (`"version"`).
`test/smoke.sh` enforces two things about it: it must be the only JSON file in
the tree that states the version, and `CHANGELOG.md` must contain a
`## [X.Y.Z]` heading for that exact version. A bump with only an
`[Unreleased]` heading fails the suite, so the bump and the stamp travel in
the same commit.

**Changelog shape: appended under `[Unreleased]`, stamped at release — with
one exception on the record.** Work commits add entries under
`## [Unreleased]`, and a release commit renames that heading to
`## [X.Y.Z] - YYYY-MM-DD` and bumps `plugin.json`. One version in the history
was instead opened directly by a work commit. Entries are accumulating under
`[Unreleased]` now, so the next release stamps it.

**Catalog: `stride-copilot-marketplace` (vendored).** The catalog holds this
tree under `plugins/stride-copilot-lite/` and lists it in
`.github/plugin/marketplace.json` with its own `version` field, plus a README
row. A sync re-vendors the tree, updates those, validates, runs the fleet
drift check and the secret scan, and tags and releases the catalog under the
catalog's own number. The catalog's `RELEASE.md` is the runbook. Because the
catalog vendors the working tree rather than a tag, it can already contain
unreleased work under the old version number — check what you are vendoring.

## Before you add to the changelog: is the top heading already tagged?

This repository is one of the three where it went wrong: a work commit
appended its entry under a numbered heading that was already tagged and
released, editing the record of a shipped version, and the next release had
to move the entry under a new heading. Check first:

```bash
git tag -l "v$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | head -n 1)"
```

It reads the newest numbered heading (skipping `[Unreleased]`). Any output
means that heading has shipped — add under `[Unreleased]`, recreating it if
needed, never under the tagged one.

## Steps

1. Run the gates (the README's "Running the test suites" section lists them):

   ```bash
   bash test/smoke.sh
   bash hooks/test-stride-copilot-lite-hook.sh
   pwsh -File hooks/test-stride-copilot-lite-hook.ps1
   ```

   and the fleet drift check from the `stride` repository
   (`bash scripts/check-port-canon.sh`, run there).

2. Run the top-heading check. Then, in one commit on `main`, rename
   `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and set `"version"` in
   `plugin.json` to `X.Y.Z`. Re-run `bash test/smoke.sh`, which now checks
   the pair, and push `main`.

3. Tag the release commit (annotated) and push the tag:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

4. Publish the GitHub release from the stamped entry:

   ```bash
   gh release create vX.Y.Z --repo cheezy/stride-copilot-lite --notes-file <notes.md>
   ```

5. Re-vendor into `stride-copilot-marketplace` per its `RELEASE.md`, then tag
   and release the catalog.

## Known gaps on the record

- Every version so far has a tag and a GitHub release.
- Older tags are a mix of annotated and lightweight; use annotated.
