#!/usr/bin/env node
// Dependency-free validation smoke test for the launchdarkly-copilot plugin.
//
//   node scripts/validate.mjs
//
// Runs on plain Node (no `npm install`, no third-party packages). Collects every
// violation, prints them, and exits non-zero if any are found; exits 0 when the
// plugin is internally consistent. Checks:
//
//   1. Version parity  — plugin.json version equals the top CHANGELOG entry, the
//      README Status line, and (when the vendored marketplace repo is available)
//      the stride-copilot-marketplace plugin entry + README Plugins-table row.
//   2. Inventory       — every skills/*/SKILL.md has name+description frontmatter,
//      the agent has a non-empty tools list, and the README component index maps
//      to the files on disk one-to-one.
//   3. References      — every namespaced skills/agents link in the README
//      resolves to a real file.
//   4. v3 drift guard  — the legacy v3 package/API identifiers appear ONLY inside
//      the labeled "## Legacy v3" section of the typescript-client skill.
//
// plugin.json is the single source of truth for the version; every other
// version-bearing artifact is compared to it (never hardcoded here).

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDir, '..'); // plugin root (parent of scripts/)

const errors = [];
const fail = (msg) => errors.push(msg);
const read = (p) => readFileSync(p, 'utf8');
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Minimal YAML-frontmatter reader: top-level `key: value` plus `key: |` / `key: >`
// block scalars. Enough for name/description/tools — no third-party YAML parser.
function parseFrontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const lines = m[1].split('\n');
  const obj = {};
  for (let i = 0; i < lines.length; i++) {
    const km = lines[i].match(/^([A-Za-z0-9_-]+):[ \t]*(.*)$/);
    if (!km) continue; // indented continuation lines are consumed by block scalars
    const key = km[1];
    let val = km[2];
    // Collect an indented body when the inline value is a block scalar (`|`/`>`)
    // OR empty — the latter covers a block sequence (`- item`) or nested mapping,
    // e.g. a YAML-list `tools:`. Consecutive indented (or blank) lines belong to
    // this key; the next unindented line ends it.
    if (/^[|>][-+]?$/.test(val.trim()) || val.trim() === '') {
      const collected = [];
      let j = i + 1;
      for (; j < lines.length; j++) {
        if (/^\s+\S/.test(lines[j]) || lines[j].trim() === '') collected.push(lines[j].trim());
        else break;
      }
      const body = collected.join('\n').trim();
      if (body !== '') {
        val = body;
        i = j - 1;
      }
    }
    obj[key] = val;
  }
  return obj;
}

// ---- source of truth: plugin.json version ----
let pluginJson;
try {
  pluginJson = JSON.parse(read(join(root, 'plugin.json')));
} catch (e) {
  console.error(`FATAL: cannot read/parse plugin.json: ${e.message}`);
  process.exit(1);
}
const version = pluginJson.version;
const pluginName = pluginJson.name;
if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
  console.error(`FATAL: plugin.json has no valid semver version (got: ${version})`);
  process.exit(1);
}

// ---- Check 1: version parity ----
// Top CHANGELOG entry (first "## [x.y.z]"; the unreleased placeholder has no semver).
const changelog = read(join(root, 'CHANGELOG.md'));
const clMatch = changelog.match(/^##\s*\[(\d+\.\d+\.\d+)\]/m);
if (!clMatch) fail('CHANGELOG.md: no released "## [x.y.z]" entry found');
else if (clMatch[1] !== version) fail(`version parity: CHANGELOG top entry ${clMatch[1]} != plugin.json ${version}`);

// README Status line.
const readme = read(join(root, 'README.md'));
const statusMatch = readme.match(/\*\*Status:\*\*\s*v?(\d+\.\d+\.\d+)/);
if (!statusMatch) fail('README.md: no "**Status:** vX.Y.Z" line found');
else if (statusMatch[1] !== version) fail(`version parity: README Status ${statusMatch[1]} != plugin.json ${version}`);

// Vendored marketplace parity (enforced when the sibling repo is available).
const mpCandidates = [
  process.env.STRIDE_COPILOT_MARKETPLACE,
  resolve(root, '..', 'stride-copilot-marketplace'),
].filter(Boolean);
const mpRoot = mpCandidates.find((p) => existsSync(join(p, '.github', 'plugin', 'marketplace.json')));
if (!mpRoot) {
  console.warn(
    `NOTE: stride-copilot-marketplace not found (looked in: ${mpCandidates.join(', ')}); ` +
      'skipping marketplace parity. Set STRIDE_COPILOT_MARKETPLACE to enable it.',
  );
} else {
  const mp = JSON.parse(read(join(mpRoot, '.github', 'plugin', 'marketplace.json')));
  const entry = (mp.plugins || []).find((p) => p.name === pluginName);
  if (!entry) fail(`marketplace.json: no plugin entry named "${pluginName}"`);
  else if (entry.version !== version) fail(`version parity: marketplace.json entry ${entry.version} != plugin.json ${version}`);

  const mpReadme = read(join(mpRoot, 'README.md'));
  const rowRe = new RegExp('\\[`' + escapeRe(pluginName) + '`\\]\\([^)]*\\)\\s*\\|\\s*(\\d+\\.\\d+\\.\\d+)\\s*\\|');
  const rowMatch = mpReadme.match(rowRe);
  if (!rowMatch) fail(`marketplace README: no Plugins-table row for "${pluginName}"`);
  else if (rowMatch[1] !== version) fail(`version parity: marketplace README table row ${rowMatch[1]} != plugin.json ${version}`);
}

// ---- Check 2: inventory (frontmatter + one-to-one README index) ----
const skillsDir = join(root, 'skills');
const skillDirs = readdirSync(skillsDir).filter((d) => statSync(join(skillsDir, d)).isDirectory());
const diskSkills = new Set();
for (const d of skillDirs) {
  const skillPath = join(skillsDir, d, 'SKILL.md');
  if (!existsSync(skillPath)) {
    fail(`skills/${d}: missing SKILL.md`);
    continue;
  }
  diskSkills.add(d);
  const fm = parseFrontmatter(read(skillPath));
  if (!fm) {
    fail(`skills/${d}/SKILL.md: missing YAML frontmatter`);
    continue;
  }
  if (!fm.name) fail(`skills/${d}/SKILL.md: frontmatter missing 'name'`);
  else if (fm.name !== d) fail(`skills/${d}/SKILL.md: frontmatter name '${fm.name}' != directory '${d}'`);
  if (!fm.description) fail(`skills/${d}/SKILL.md: frontmatter missing 'description'`);
}

const agentsDir = join(root, 'agents');
const agentFiles = existsSync(agentsDir)
  ? readdirSync(agentsDir).filter((f) => f.endsWith('.agent.md'))
  : [];
if (agentFiles.length === 0) fail('agents/: no *.agent.md file found');
for (const f of agentFiles) {
  const fm = parseFrontmatter(read(join(agentsDir, f)));
  if (!fm) {
    fail(`agents/${f}: missing YAML frontmatter`);
    continue;
  }
  if (!fm.name) fail(`agents/${f}: frontmatter missing 'name'`);
  const tools = (fm.tools || '').trim();
  const hasTools = /\[.*\S.*\]/.test(tools) || /^-\s+\S/m.test(tools);
  if (!hasTools) fail(`agents/${f}: frontmatter missing a non-empty 'tools' list`);
}

// README component index must map to disk one-to-one.
const readmeSkillRefs = new Set([...readme.matchAll(/skills\/([a-z0-9-]+)\/SKILL\.md/g)].map((m) => m[1]));
for (const s of diskSkills) if (!readmeSkillRefs.has(s)) fail(`README index: skill '${s}' on disk but not indexed`);
for (const s of readmeSkillRefs) if (!diskSkills.has(s)) fail(`README index: skill '${s}' indexed but not on disk`);

const readmeAgentRefs = new Set([...readme.matchAll(/agents\/([A-Za-z0-9._-]+\.agent\.md)/g)].map((m) => m[1]));
const diskAgents = new Set(agentFiles);
for (const a of diskAgents) if (!readmeAgentRefs.has(a)) fail(`README index: agent '${a}' on disk but not indexed`);
for (const a of readmeAgentRefs) if (!diskAgents.has(a)) fail(`README index: agent '${a}' indexed but not on disk`);

// ---- Check 3: namespaced references resolve ----
for (const m of readme.matchAll(/\]\((skills\/[^)]+|agents\/[^)]+)\)/g)) {
  const rel = m[1];
  if (!existsSync(join(root, rel))) fail(`README link does not resolve: ${rel}`);
}

// ---- Check 4: v3 package-era drift guard (typescript-client skill only) ----
const tsClientPath = join(root, 'skills', 'launchdarkly-typescript-client', 'SKILL.md');
if (!existsSync(tsClientPath)) {
  fail('skills/launchdarkly-typescript-client/SKILL.md: missing');
} else {
  const tsClient = read(tsClientPath);
  const legacyIdx = tsClient.search(/^##\s+Legacy v3\b/m);
  if (legacyIdx === -1) {
    fail('typescript-client SKILL.md: no "## Legacy v3" section heading found');
  } else {
    // Scope the legacy allowance to the labeled legacy section ONLY: the primary
    // content (everything before the heading) must be free of v3 identifiers,
    // while legitimate v3 mentions inside the legacy section are tolerated.
    const primary = tsClient.slice(0, legacyIdx);
    const v3Patterns = [
      ['launchdarkly-js-client-sdk', /launchdarkly-js-client-sdk/],
      ['launchdarkly-react-client-sdk', /launchdarkly-react-client-sdk/],
      ['withLDProvider', /withLDProvider/],
      ['asyncWithLDProvider', /asyncWithLDProvider/],
      ['useFlags', /useFlags/],
      ['initialize(', /\binitialize\(/],
    ];
    for (const [name, re] of v3Patterns) {
      if (re.test(primary)) {
        fail(`v3 drift: legacy identifier '${name}' appears in typescript-client SKILL.md outside the "## Legacy v3" section`);
      }
    }
  }
}

// ---- report ----
if (errors.length > 0) {
  console.error(`\nvalidate: ${errors.length} violation(s) found:`);
  for (const e of errors) console.error(`  ✗ ${e}`);
  process.exit(1);
}
console.log(`validate: all checks passed (v${version}, ${diskSkills.size} skills, ${agentFiles.length} agent) ✓`);
process.exit(0);
