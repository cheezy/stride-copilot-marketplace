# End-to-end smoke test for the stride-ideation-stridify pipeline.
# PowerShell mirror of run_smoke_test.sh — exercises the helpers the
# stridify skill reaches through Step 3, Step 8a and lib/ship.ps1
# (validate_batch.py, read_auth.py, strip_audit_fields.py) and verifies
# each produces the expected output; the stage order is this runner's own,
# not the skill's.
# The other stages are checks the skill itself never runs: Stage 2
# (drift_check.py on the fixture), Stage 5 (a canned 2xx response rendered
# in the Step 10 table format; the real renderer is covered by
# lib/test-ship.ps1) and Stage 6 (the challenge-gate fixture's shape). The final HTTP POST is dry-run
# by default; pass -Live <stride-batch.json> to POST against a real
# Stride instance using the auth in .stride_auth.md.
#
# Usage:
#   pwsh -File lib\run_smoke_test.ps1
#       Dry-run mode. Uses fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json.
#
#   pwsh -File lib\run_smoke_test.ps1 -Live <stride-batch.json>
#       LIVE mode. Ships the supplied batch through lib/ship.ps1, which
#       reads .stride_auth.md ($env:STRIDE_AUTH_FILE, else the git toplevel,
#       else the current directory) and POSTs it to the Stride API. On a
#       non-2xx it prints the response body verbatim. Use a dev Stride
#       instance — this creates real tasks.
#
# Exit code: 0 if every stage passes; 1 on the first failure.

param(
    [Parameter(Mandatory = $false)] [string]$Live
)

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$Mode = if ($Live) { 'live' } else { 'dry' }
$BatchPath = if ($Live) { $Live } else { Join-Path $PluginRoot 'fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json' }

$script:PASS = 0
$script:FAIL = 0

function Pass([string]$message) {
    $script:PASS++
    Write-Host "  ✓  $message"
}

function Fail([string]$message, [string]$detail = '') {
    $script:FAIL++
    Write-Host "  ✗  $message"
    if ($detail) { Write-Host "     $detail" }
}

Write-Host "stride-ideation smoke test ($Mode mode)"
Write-Host "batch JSON: $BatchPath"
Write-Host ""

# --- Stage 1: validate_batch.py ---------------------------------------------

Write-Host 'Stage 1: structural validation'
$validateErr = New-TemporaryFile
$validateOut = & python3 (Join-Path $ScriptDir 'validate_batch.py') $BatchPath 2>$validateErr.FullName
if ($LASTEXITCODE -eq 0) {
    Pass "validate_batch.py accepts the batch"
} else {
    $errText = Get-Content -Raw -LiteralPath $validateErr.FullName -ErrorAction SilentlyContinue
    Fail "validate_batch.py rejected the batch" $errText
}
Remove-Item -Force $validateErr.FullName -ErrorAction SilentlyContinue

# --- Stage 2: drift_check.py ------------------------------------------------

Write-Host ''
Write-Host 'Stage 2: fixture source-spec drift check (drift_check.py; not a skill step)'
$driftErr = New-TemporaryFile
$driftOut = & python3 (Join-Path $ScriptDir 'drift_check.py') $BatchPath 2>$driftErr.FullName
$driftExit = $LASTEXITCODE
$driftErrText = Get-Content -Raw -LiteralPath $driftErr.FullName -ErrorAction SilentlyContinue
switch ($driftExit) {
    0 { Pass "drift_check.py reports no drift (source_spec_sha256 matches the source)" }
    1 { Fail "drift_check.py reports DRIFT — fixture is stale" $driftErrText }
    2 { Fail "drift_check.py reported an error" $driftErrText }
    default { Fail "drift_check.py exited unexpectedly (code $driftExit)" $driftErrText }
}
Remove-Item -Force $driftErr.FullName -ErrorAction SilentlyContinue

# --- Stage 3: read_auth.py against a fixture auth file ---------------------

Write-Host ''
Write-Host 'Stage 3: auth file parsing'
$tmpAuth = New-TemporaryFile
Set-Content -LiteralPath $tmpAuth.FullName -Value @"
- **API URL:** ``https://www.stridelikeaboss.example``
- **Local API Token:** ``stride_dev_LOCAL_should_not_match``
- **API Token:** ``stride_dev_TEST_TOKEN_FOR_SMOKE_TEST_ONLY``
"@ -Encoding UTF8

$authErr = New-TemporaryFile
$authOut = & python3 (Join-Path $ScriptDir 'read_auth.py') $tmpAuth.FullName 2>$authErr.FullName
if ($LASTEXITCODE -eq 0) {
    if ($authOut -match '(?m)^STRIDE_API_URL=https://www\.stridelikeaboss\.example$') {
        Pass "read_auth.py extracts STRIDE_API_URL"
    } else {
        Fail "URL line not as expected" ($authOut -join "`n")
    }
    if ($authOut -match '(?m)^STRIDE_API_TOKEN=stride_dev_TEST_TOKEN_FOR_SMOKE_TEST_ONLY$') {
        Pass "read_auth.py extracts the API Token (and not the Local API Token)"
    } else {
        Fail "TOKEN line not as expected" ($authOut -join "`n")
    }
} else {
    $errText = Get-Content -Raw -LiteralPath $authErr.FullName -ErrorAction SilentlyContinue
    Fail "read_auth.py failed on the fixture auth file" $errText
}
Remove-Item -Force $tmpAuth.FullName, $authErr.FullName -ErrorAction SilentlyContinue

# --- Stage 4: strip_audit_fields.py ----------------------------------------

Write-Host ''
Write-Host 'Stage 4: strip local-audit fields from the payload'
$shaBefore = (Get-FileHash -LiteralPath $BatchPath -Algorithm SHA256).Hash.ToLowerInvariant()
$stripErr = New-TemporaryFile
$stripped = & python3 (Join-Path $ScriptDir 'strip_audit_fields.py') $BatchPath 2>$stripErr.FullName
if ($LASTEXITCODE -eq 0) {
    $strippedText = ($stripped -join "`n")
    if ($strippedText -match '"source_spec"') {
        Fail "stripped payload still contains source_spec"
    } else {
        Pass "source_spec removed from payload"
    }
    if ($strippedText -match '"source_spec_sha256"') {
        Fail "stripped payload still contains source_spec_sha256"
    } else {
        Pass "source_spec_sha256 removed from payload"
    }
    if ($strippedText -match '"decomposition_notes"') {
        Fail "stripped payload still contains decomposition_notes"
    } else {
        Pass "decomposition_notes removed from payload"
    }
    if ($strippedText -match '"goals"') {
        Pass "stripped payload still contains goals"
    } else {
        Fail "stripped payload lost goals"
    }
} else {
    $errText = Get-Content -Raw -LiteralPath $stripErr.FullName -ErrorAction SilentlyContinue
    Fail "strip_audit_fields.py failed" $errText
}
Remove-Item -Force $stripErr.FullName -ErrorAction SilentlyContinue

# Confirm the on-disk file is unchanged: the strip writes only to stdout.
$shaAfter = (Get-FileHash -LiteralPath $BatchPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($shaBefore -and $shaBefore -eq $shaAfter) {
    Pass "on-disk batch JSON unchanged after strip (SHA-256 $shaAfter before and after)"
} else {
    Fail 'on-disk batch JSON changed during the strip' "before=$shaBefore after=$shaAfter"
}

# --- Stage 5: response-rendering (canned 2xx) ------------------------------

Write-Host ''
Write-Host 'Stage 5: render created-identifiers table from a mock 2xx response'
$cannedResponse = @"
{
  "data": {
    "goals": [
      {
        "identifier": "G999",
        "title": "Smoke test goal",
        "tasks": [
          {"identifier": "W9001", "title": "Smoke test task 1"},
          {"identifier": "W9002", "title": "Smoke test task 2"}
        ]
      }
    ]
  }
}
"@

$rendered = $cannedResponse | & python3 -c @"
import json, sys
data = json.load(sys.stdin)
container = data.get('data', data)
goals = container.get('goals', [])
for goal in goals:
    gid = goal.get('identifier', '?')
    title = goal.get('title', '')
    print(f'  {gid:>6}  {title}')
    for task in goal.get('tasks', []) or []:
        tid = task.get('identifier', '?')
        ttitle = task.get('title', '')
        print(f'  {tid:>6}    {ttitle}')
"@

$renderedText = ($rendered -join "`n")
if ($renderedText -match 'G999  Smoke test goal' -and
    $renderedText -match 'W9001    Smoke test task 1' -and
    $renderedText -match 'W9002    Smoke test task 2') {
    Pass "render code produces a two-column G/W table from a 2xx body"
} else {
    Fail "render output not as expected" $renderedText
}

# --- Stage 6: challenge-gate fixture shape ---------------------------------

Write-Host ''
Write-Host 'Stage 6: challenge-gate fixture shape'
$gateFixture = Join-Path $PluginRoot 'fixtures/2026-05-12T120300-saved-filters-challenge-gate-requirements.md'
if (Test-Path -LiteralPath $gateFixture) {
    $gateLines = Get-Content -LiteralPath $gateFixture

    if ($gateLines | Where-Object { $_ -match '^## Design challenge\s*$' }) {
        Pass "challenge-gate fixture has a '## Design challenge' section"
    } else {
        Fail "challenge-gate fixture is missing the '## Design challenge' section"
    }

    $altCount = @($gateLines | Where-Object { $_ -match '\*\*Alternative [A-Z]' }).Count
    if ($altCount -ge 2) {
        Pass "Design challenge names at least two alternatives"
    } else {
        Fail "Design challenge has fewer than two alternatives"
    }

    $dimsOk = $true
    foreach ($dim in @('Cost', 'Risk', 'Complexity', 'Timeline')) {
        if (-not ($gateLines | Where-Object { $_ -match "(?i)^\s*\|\s*$dim\s*\|" })) {
            $dimsOk = $false
        }
    }
    if ($dimsOk) {
        Pass "trade-off comparison covers cost, risk, complexity, and timeline"
    } else {
        Fail "trade-off comparison is missing one of the four dimensions"
    }

    $inAssumptions = $false
    $hasRating = $false
    foreach ($line in $gateLines) {
        if ($line -match '^## Assumptions\s*$') { $inAssumptions = $true; continue }
        if ($inAssumptions -and $line -match '^## ') { $inAssumptions = $false }
        if ($inAssumptions -and $line -match '\((high|medium|low)\)') { $hasRating = $true }
    }
    if ($hasRating) {
        Pass "Assumptions section shows per-assumption confidence ratings"
    } else {
        Fail "no (high)/(medium)/(low) confidence ratings under Assumptions"
    }
} else {
    Fail "challenge-gate fixture not found" $gateFixture
}

# --- Stage 7: LIVE POST (only if -Live) ------------------------------------

if ($Mode -eq 'live') {
    Write-Host ''
    Write-Host 'Stage 7: LIVE POST to the Stride API (NOTE: creates real tasks)'
    # Ship through lib/ship.ps1 — the PowerShell twin of the lib/ship.sh call
    # the stridify skill's Step 9 makes — in a child pwsh so its exit code is
    # real. Its stdout and stderr (verbatim body on failure, identifier table
    # on success) pass straight through.
    $pwshExe = (Get-Process -Id $PID).Path
    & $pwshExe -NoProfile -NonInteractive -File (Join-Path $ScriptDir 'ship.ps1') -Batch $BatchPath
    if ($LASTEXITCODE -eq 0) {
        Pass 'live: lib/ship.ps1 shipped the batch'
    } else {
        Fail 'live: lib/ship.ps1 exited non-zero (its stderr is above)'
    }
}

# --- summary ---------------------------------------------------------------

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) {
    exit 1
} else {
    exit 0
}
