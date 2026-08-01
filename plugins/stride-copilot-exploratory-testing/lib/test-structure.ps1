# PowerShell mirror of test-structure.sh — structure smoke test for the
# stride-copilot-exploratory-testing plugin.
#
# Asserts the plugin ships every file the Copilot plugin schema and this
# plugin's docs require: a valid ROOT manifest, all six core knowledge
# skills, all seven command-derived skills, both .agent.md agents, the three
# README-referenced fixtures, and the root docs. No network, no jq (JSON via
# ConvertFrom-Json).
#
# Copilot conventions: plugin.json at the repository ROOT, agents use the
# .agent.md extension, and there is NO commands/ directory.
#
# Exit code: 0 if every check passes; 1 if any check fails.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'stride-copilot-exploratory-testing structure smoke test'
Write-Host "plugin root: $PluginRoot"
Write-Host ''

# --- Manifest (ROOT plugin.json) -------------------------------------------

$Manifest = Join-Path $PluginRoot 'plugin.json'
if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
    try {
        $json = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
        Pass 'plugin.json exists at the root and is valid JSON'
        $required = @('name', 'description', 'version', 'agents', 'skills')
        $missing = @($required | Where-Object { -not ($json.PSObject.Properties.Name -contains $_) })
        if ($missing.Count -eq 0) {
            Pass 'plugin.json has the required keys (name, description, version, agents, skills)'
        }
        else {
            Fail 'plugin.json is missing required key(s)' ($missing -join ', ')
        }
    }
    catch {
        Fail 'plugin.json is not valid JSON' $_.Exception.Message
    }
}
else {
    Fail 'plugin.json not found at the plugin root' $Manifest
}

# --- Core knowledge skills -------------------------------------------------

foreach ($skill in @('stride-exploratory-testing', 'chartering', 'heuristics', 'oracles', 'bug-advocacy', 'session')) {
    $p = Join-Path $PluginRoot "skills/$skill/SKILL.md"
    if (Test-Path -LiteralPath $p -PathType Leaf) { Pass "skills/$skill/SKILL.md exists" }
    else { Fail "skills/$skill/SKILL.md is missing" }
}

# --- Command-derived skills (replace the upstream slash commands) -----------

foreach ($skill in @(
        'stride-exploratory-testing-charter',
        'stride-exploratory-testing-nightmare-headline',
        'stride-exploratory-testing-explore',
        'stride-exploratory-testing-recon',
        'stride-exploratory-testing-debrief',
        'stride-exploratory-testing-pair',
        'stride-exploratory-testing-harden')) {
    $p = Join-Path $PluginRoot "skills/$skill/SKILL.md"
    if (Test-Path -LiteralPath $p -PathType Leaf) { Pass "skills/$skill/SKILL.md exists" }
    else { Fail "skills/$skill/SKILL.md is missing" }
}

# Count only real SKILL.md files (any .gitkeep placeholder is ignored).
$skillCount = @(Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'skills') -Directory |
    ForEach-Object { Join-Path $_.FullName 'SKILL.md' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count
if ($skillCount -eq 13) {
    Pass 'exactly 13 SKILL.md files present (6 core + 7 command-derived; .gitkeep ignored)'
}
else {
    Fail "expected 13 SKILL.md files, found $skillCount"
}

# --- Agents (.agent.md extension) ------------------------------------------

foreach ($agent in @('charter-generator', 'explorer')) {
    $p = Join-Path $PluginRoot "agents/$agent.agent.md"
    if (Test-Path -LiteralPath $p -PathType Leaf) { Pass "agents/$agent.agent.md exists" }
    else { Fail "agents/$agent.agent.md is missing" }
}

# Count only *.agent.md files (any .gitkeep placeholder is ignored).
$agentCount = @(Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'agents') -Filter '*.agent.md' -File).Count
if ($agentCount -eq 2) {
    Pass 'exactly 2 agent files present (.gitkeep ignored)'
}
else {
    Fail "expected 2 agent files, found $agentCount"
}

# --- Fixtures (referenced by README.md) ------------------------------------

foreach ($fixture in @('example-charters.md', 'example-session-sheet.md', 'example-debrief.md')) {
    $p = Join-Path $PluginRoot "fixtures/$fixture"
    if (Test-Path -LiteralPath $p -PathType Leaf) { Pass "fixtures/$fixture exists" }
    else { Fail "fixtures/$fixture is missing" }
}

# --- Root docs -------------------------------------------------------------

foreach ($doc in @('README.md', 'CHANGELOG.md', 'LICENSE')) {
    $p = Join-Path $PluginRoot $doc
    if (Test-Path -LiteralPath $p -PathType Leaf) { Pass "$doc exists" }
    else { Fail "$doc is missing" }
}

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
