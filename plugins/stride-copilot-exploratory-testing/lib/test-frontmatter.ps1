# PowerShell mirror of test-frontmatter.sh — frontmatter smoke test for the
# stride-copilot-exploratory-testing plugin.
#
# Asserts every skill and agent carries the YAML frontmatter keys Copilot
# needs to load it:
#   - skills/*/SKILL.md    : name, description
#   - agents/*.agent.md    : name, description, tools   (description may be a
#                            `description: |` block scalar)
# No network, no jq. Copilot agents use the .agent.md extension, and there is
# no commands/ directory to check.
#
# Exit code: 0 if every check passes; 1 if any check fails.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

# Return the YAML frontmatter lines (between the first two `---` fences).
# Requires the file to open with `---` on line 1.
function Get-Frontmatter($path) {
    $lines = Get-Content -LiteralPath $path
    $fences = 0
    $block = @()
    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            $fences++
            if ($fences -ge 2) { break }
            continue
        }
        if ($fences -eq 1) { $block += $line }
    }
    return $block
}

# True when the frontmatter declares KEY (matches `key:` at the start of a
# line — works for inline values and `key: |` block scalars alike).
function Test-HasKey($frontmatter, $key) {
    foreach ($line in $frontmatter) {
        if ($line -match ("^" + [regex]::Escape($key) + ":")) { return $true }
    }
    return $false
}

# Check that FILE (relative label, path) declares every key in $Keys.
function Test-Keys($label, $file, [string[]]$Keys) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Fail "$label is missing" $file
        return
    }
    $fm = Get-Frontmatter $file
    $missing = @($Keys | Where-Object { -not (Test-HasKey $fm $_) })
    if ($missing.Count -eq 0) {
        Pass ("{0} declares: {1}" -f $label, ($Keys -join ' '))
    }
    else {
        Fail "$label is missing frontmatter key(s)" ($missing -join ' ')
    }
}

Write-Host 'stride-copilot-exploratory-testing frontmatter smoke test'
Write-Host "plugin root: $PluginRoot"
Write-Host ''

# --- Skills: name + description --------------------------------------------

Write-Host 'Skills (name, description)'
$skillFiles = @(Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'skills') -Directory |
    ForEach-Object { Join-Path $_.FullName 'SKILL.md' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($skillFiles.Count -eq 0) {
    Fail 'no SKILL.md files found under skills/'
}
else {
    foreach ($skillMd in $skillFiles) {
        $rel = 'skills/' + (Split-Path -Leaf (Split-Path -Parent $skillMd)) + '/SKILL.md'
        Test-Keys $rel $skillMd @('name', 'description')
    }
}

# --- Agents: name + description + tools ------------------------------------

Write-Host ''
Write-Host 'Agents (name, description, tools)'
$agentFiles = @(Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'agents') -Filter '*.agent.md' -File)
if ($agentFiles.Count -eq 0) {
    Fail 'no *.agent.md files found under agents/'
}
else {
    foreach ($agentMd in $agentFiles) {
        $rel = 'agents/' + $agentMd.Name
        Test-Keys $rel $agentMd.FullName @('name', 'description', 'tools')
    }
}

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
