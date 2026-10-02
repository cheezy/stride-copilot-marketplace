# PowerShell mirror of test-stridify-preview.sh — exercises the
# stride-ideation-stridify Step 8.5 preview-and-approval gate, the Step 1
# --yes / --auto-approve bypass (W1147) and the Step 1 / 1b --batch mode
# (W2193) documented in skills/stride-ideation-stridify/SKILL.md.
#
# The platform question UI is only available inside a live Copilot CLI session,
# so this test embeds a reference implementation of the documented flag parse +
# preview render + gate and exercises it against a fixture batch JSON. The human
# approve / decline answer is injected as a parameter (standing in for the
# prompt result). The reference implementations MUST stay consistent with
# Step 1 and Step 8.5 in skills/stride-ideation-stridify/SKILL.md and with the
# bash mirror lib/test-stridify-preview.sh — if you edit one, edit all.
#
# Run:
#   pwsh -File lib/test-stridify-preview.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-stridify-preview.ps1 — exercises the Step 8.5 preview gate + --yes bypass'
Write-Host ''

# --- reference --yes / --auto-approve parser -------------------------------
# Mirrors SKILL.md Step 1. Returns a hashtable @{ AutoApprove; Remainder }.
function Parse-YesFlag([string]$ArgString) {
    $tokens = @($ArgString -split '\s+' | Where-Object { $_ -ne '' })
    $yes = $false
    $rest = @()
    foreach ($t in $tokens) {
        if ($t -eq '--yes' -or $t -eq '--auto-approve') { $yes = $true }
        else { $rest += $t }
    }
    return @{ AutoApprove = $yes; Remainder = ($rest -join ' ') }
}

# --- reference --batch parser ------------------------------------------------
# Mirrors SKILL.md Step 1's --batch rules. Returns
#   batch=<path>|yes=<true|false>|err=<usage|goal|doc|>|rest=<remainder>
function Parse-BatchArgs([string]$ArgString) {
    $toks = @($ArgString -split '\s+' | Where-Object { $_ -ne '' })
    $batch = ''; $haveBatch = $false; $goal = ''; $yes = $false; $rest = @(); $err = ''
    for ($i = 0; $i -lt $toks.Count; $i++) {
        $t = $toks[$i]
        if ($t -ceq '--batch') {
            $haveBatch = $true
            if ($i + 1 -lt $toks.Count -and -not $toks[$i + 1].StartsWith('--')) { $batch = $toks[$i + 1]; $i++ } else { $err = 'usage' }
        } elseif ($t.StartsWith('--batch=')) {
            $haveBatch = $true; $batch = $t.Substring(8); if (-not $batch) { $err = 'usage' }
        } elseif ($t -ceq '--goal') {
            if ($i + 1 -lt $toks.Count) { $goal = $toks[$i + 1] }; $i++
        } elseif ($t.StartsWith('--goal=')) {
            $goal = $t.Substring(7)
        } elseif ($t -ceq '--yes' -or $t -ceq '--auto-approve') {
            $yes = $true
        } else {
            $rest += $t
        }
    }
    $restText = $rest -join ' '
    if (-not $err) {
        if ($haveBatch -and $goal) { $err = 'goal' }
        elseif ($haveBatch -and $restText) { $err = 'doc' }
        elseif (-not $haveBatch -and -not $restText) { $err = 'usage' }
    }
    return "batch=$batch|yes=$($yes.ToString().ToLowerInvariant())|err=$err|rest=$restText"
}

# --- reference preview render ----------------------------------------------
# Mirrors SKILL.md Step 8.5a. Reads ONLY the on-disk batch JSON (no auth
# material) and returns the goal/task tree + cross-goal claim order as text.
function Render-Preview([string]$BatchPath) {
    $data = Get-Content -LiteralPath $BatchPath -Raw | ConvertFrom-Json
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('') | Out-Null
    $lines.Add('Goals and tasks to be created:') | Out-Null
    $lines.Add('') | Out-Null
    foreach ($goal in @($data.goals)) {
        $title = if ($goal.PSObject.Properties['title'] -and $goal.title) { $goal.title } else { '(no title)' }
        $tasks = if ($goal.PSObject.Properties['tasks'] -and $goal.tasks) { @($goal.tasks) } else { @() }
        $n = $tasks.Count
        $plural = if ($n -ne 1) { 's' } else { '' }
        $lines.Add("  Goal: $title  ($n task$plural)") | Out-Null
        foreach ($task in $tasks) {
            $tt = if ($task.PSObject.Properties['title'] -and $task.title) { $task.title } else { '(no title)' }
            $lines.Add("    - $tt") | Out-Null
        }
    }
    $lines.Add('') | Out-Null
    $notes = if ($data.PSObject.Properties['decomposition_notes']) { $data.decomposition_notes } else { '' }
    if ($notes) {
        $lines.Add('Cross-goal claim order:') | Out-Null
        $lines.Add("  $notes") | Out-Null
        $lines.Add('') | Out-Null
    }
    return ($lines -join "`n")
}

# --- reference preview + gate ----------------------------------------------
# Mirrors SKILL.md Step 8.5 a/b/c. Writes the combined output to $LogPath. On
# bypass ($AutoApprove) or an explicit approve, writes the POST sentinel
# (proceed to Step 9) and returns 0. On decline it appends the clean-stop
# message and returns 10 WITHOUT writing the sentinel or touching the JSON.
function Render-AndGate([string]$BatchPath, [bool]$AutoApprove, [string]$Answer, [string]$SentinelPath, [string]$LogPath) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add((Render-Preview $BatchPath)) | Out-Null
    if ($AutoApprove) {
        Set-Content -LiteralPath $SentinelPath -Value 'POST_ATTEMPTED'
        Set-Content -LiteralPath $LogPath -Encoding UTF8 -Value ($out -join "`n")
        return 0
    }
    if ($Answer -eq 'approve') {
        Set-Content -LiteralPath $SentinelPath -Value 'POST_ATTEMPTED'
        Set-Content -LiteralPath $LogPath -Encoding UTF8 -Value ($out -join "`n")
        return 0
    }
    $out.Add("stride-ideation: declined. The batch JSON is on disk at $BatchPath; no POST was attempted.") | Out-Null
    $out.Add("Ship it later, unchanged, by activating stride-ideation-stridify with: --batch `"$BatchPath`"") | Out-Null
    Set-Content -LiteralPath $LogPath -Encoding UTF8 -Value ($out -join "`n")
    return 10
}

# === temp dir + fixtures ===================================================

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('stipreview_' + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmpDir | Out-Null

$batch = Join-Path $tmpDir '2026-05-12T120000-fixture-stride-batch.json'
Set-Content -LiteralPath $batch -Encoding UTF8 -Value @'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "decomposition_notes": "Claim Goal A (data layer) first; Goal B (UI) depends on A's API surface.",
  "goals": [
    {
      "title": "Goal A — data layer",
      "type": "goal",
      "tasks": [
        { "title": "Create the schema migration" },
        { "title": "Add the context module" }
      ]
    },
    {
      "title": "Goal B — UI layer",
      "type": "goal",
      "tasks": [
        { "title": "Wire the LiveView" }
      ]
    }
  ]
}
'@

$single = Join-Path $tmpDir '2026-05-12T120000-fixture-kanban-app-stride-batch.json'
Set-Content -LiteralPath $single -Encoding UTF8 -Value @'
{
  "source_spec": "2026-05-12T120000-fixture-requirements.md",
  "source_spec_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
  "decomposition_notes": "Single-goal shape, no cross-goal coordination.",
  "goals": [
    {
      "title": "Kanban app — review queue",
      "type": "goal",
      "tasks": [
        { "title": "Add the review column" }
      ]
    }
  ]
}
'@

$sentinel = Join-Path $tmpDir 'post_was_attempted'
$shaBefore = (Get-FileHash -LiteralPath $batch -Algorithm SHA256).Hash

try {
    # === case 1: --yes / --auto-approve parse (both forms + absence) ========
    $rYes = Parse-YesFlag '--yes /path/to/doc.md'
    $rAuto = Parse-YesFlag '--auto-approve /path/to/doc.md'
    $rNone = Parse-YesFlag '/path/to/doc.md'
    if ($rYes.AutoApprove -eq $true -and $rAuto.AutoApprove -eq $true -and $rNone.AutoApprove -eq $false) {
        Pass 'case 1: --yes and --auto-approve set bypass=true; absence leaves bypass=false (AC3)'
    } else {
        Fail 'case 1: bypass flag parse wrong' "yes=$($rYes.AutoApprove) auto=$($rAuto.AutoApprove) none=$($rNone.AutoApprove)"
    }
    if ($rYes.Remainder -ceq '/path/to/doc.md' -and $rNone.Remainder -ceq '/path/to/doc.md') {
        Pass 'case 1: the flag token is consumed and REQUIREMENTS_PATH remainder is preserved'
    } else {
        Fail 'case 1: remainder wrong after flag consumption' "yes=[$($rYes.Remainder)] none=[$($rNone.Remainder)]"
    }

    # === case 2: bypass path reaches POST without an approval prompt (AC3) ===
    Remove-Item -Force $sentinel -ErrorAction SilentlyContinue
    $logBypass = Join-Path $tmpDir 'run_bypass.log'
    $rc = Render-AndGate $batch $true '' $sentinel $logBypass
    if ($rc -eq 0 -and (Test-Path -LiteralPath $sentinel)) {
        Pass 'case 2: --yes bypass proceeds to POST (sentinel set, rc 0)'
    } else {
        Fail 'case 2: bypass did not reach POST' "rc=$rc"
    }
    if (-not (Select-String -LiteralPath $logBypass -Pattern 'declined' -SimpleMatch -Quiet)) {
        Pass 'case 2: bypass path prints no decline / prompt text'
    } else {
        Fail 'case 2: bypass path unexpectedly printed decline text'
    }

    # === case 3: decline path does NOT POST and leaves JSON on disk (AC1/AC4) ===
    Remove-Item -Force $sentinel -ErrorAction SilentlyContinue
    $logDecline = Join-Path $tmpDir 'run_decline.log'
    $rc = Render-AndGate $batch $false 'decline' $sentinel $logDecline
    if ($rc -eq 10 -and -not (Test-Path -LiteralPath $sentinel)) {
        Pass 'case 3: decline does NOT attempt the POST (no sentinel)'
    } else {
        Fail 'case 3: decline attempted the POST (regression)' "rc=$rc"
    }
    if (Test-Path -LiteralPath $batch) {
        Pass 'case 3: declined batch JSON remains on disk'
    } else {
        Fail 'case 3: declined batch JSON was removed (regression)'
    }
    $shaAfter = (Get-FileHash -LiteralPath $batch -Algorithm SHA256).Hash
    if ($shaBefore -ceq $shaAfter) {
        Pass 'case 3: declined batch JSON is byte-for-byte unchanged (recovery artifact preserved)'
    } else {
        Fail 'case 3: declined batch JSON was rewritten (pitfall violated)'
    }
    if (Select-String -LiteralPath $logDecline -Pattern 'no POST was attempted' -SimpleMatch -Quiet) {
        Pass 'case 3: decline message states the POST was not attempted'
    } else {
        Fail "case 3: decline message missing 'no POST was attempted'"
    }
    if ((Get-Content -Raw -LiteralPath $logDecline).Contains("--batch `"$batch`"")) {
        Pass 'case 3: decline message names the --batch form for this file'
    } else {
        Fail 'case 3: decline message does not name --batch'
    }

    # === case 4: approve path proceeds to POST (AC2) =======================
    Remove-Item -Force $sentinel -ErrorAction SilentlyContinue
    $logApprove = Join-Path $tmpDir 'run_approve.log'
    $rc = Render-AndGate $batch $false 'approve' $sentinel $logApprove
    if ($rc -eq 0 -and (Test-Path -LiteralPath $sentinel)) {
        Pass 'case 4: explicit approval proceeds to POST (sentinel set, rc 0)'
    } else {
        Fail 'case 4: approval did not reach POST' "rc=$rc"
    }

    # === case 5: render lists every goal and its task count (AC1) ==========
    $preview = Render-Preview $batch
    if ($preview -match 'Goal: Goal A — data layer  \(2 tasks\)' -and $preview -match 'Goal: Goal B — UI layer  \(1 task\)') {
        Pass 'case 5: preview lists each goal with its task count (singular/plural correct)'
    } else {
        Fail 'case 5: goal/task-count render wrong' $preview
    }
    if ($preview -match '- Create the schema migration' -and $preview -match '- Add the context module' -and $preview -match '- Wire the LiveView') {
        Pass 'case 5: preview lists every task title'
    } else {
        Fail 'case 5: task titles missing from render' $preview
    }

    # === case 6: render shows cross-goal claim order from decomposition_notes (AC1, edge case) ===
    if ($preview -match 'Cross-goal claim order:' -and $preview -match 'Claim Goal A \(data layer\) first') {
        Pass 'case 6: preview shows cross-goal claim order from decomposition_notes'
    } else {
        Fail 'case 6: cross-goal claim order missing from render' $preview
    }

    # === case 7: --goal scoped (single-goal) batch renders the one goal (edge case) ===
    $previewSingle = Render-Preview $single
    $goalCount = ([regex]::Matches($previewSingle, 'Goal: ')).Count
    if ($previewSingle -match 'Goal: Kanban app — review queue  \(1 task\)' -and $goalCount -eq 1) {
        Pass 'case 7: --goal scoped batch renders exactly the single scoped goal'
    } else {
        Fail 'case 7: single-goal render wrong' $previewSingle
    }

    # === case 8: pitfall — no token / auth material in any gate output =====
    $allOut = $preview + (Get-Content -Raw -LiteralPath $logBypass) + (Get-Content -Raw -LiteralPath $logDecline) + (Get-Content -Raw -LiteralPath $logApprove)
    if ($allOut -match 'stride_(dev|prod)_' -or $allOut -match 'Bearer ' -or $allOut -match 'Authorization:') {
        Fail 'case 8: gate output contains potential auth material (pitfall violated)'
    } else {
        Pass 'case 8: no Bearer/token/Authorization strings in preview or gate output (pitfall avoided)'
    }

    # === cases 9-14: --batch parse ==========================================
    $parseCases = @(
        @('case 9: --batch <path> selects batch mode', '--batch docs/x-stride-batch.json', 'batch=docs/x-stride-batch.json|yes=false|err=|rest='),
        @('case 10: --batch=<path> splits on the first = only', '--batch=docs/a=b.json', 'batch=docs/a=b.json|yes=false|err=|rest='),
        @('case 11a: a bare trailing --batch is a usage error', '--batch', 'batch=|yes=false|err=usage|rest='),
        @('case 11b: --batch= with no value is a usage error', '--batch=', 'batch=|yes=false|err=usage|rest='),
        @('case 11c: --batch followed by a flag never takes the flag as its path', '--batch --yes', 'batch=|yes=true|err=usage|rest='),
        @('case 12: --batch together with --goal is rejected', '--batch b.json --goal 2', 'batch=b.json|yes=false|err=goal|rest='),
        @('case 12b: --goal=<v> before --batch=<v> is rejected too', '--goal=2 --batch=b.json', 'batch=b.json|yes=false|err=goal|rest='),
        @('case 13: --batch with a requirements-doc path left over is rejected', '--batch b.json docs/x-requirements.md', 'batch=b.json|yes=false|err=doc|rest=docs/x-requirements.md'),
        @('case 14a: --batch --yes keeps the path and sets the bypass', '--batch b.json --yes', 'batch=b.json|yes=true|err=|rest='),
        @('case 14b: no --batch and no doc path is a usage error', '--yes', 'batch=|yes=true|err=usage|rest=')
    )
    foreach ($c in $parseCases) {
        $got = Parse-BatchArgs $c[1]
        if ($got -ceq $c[2]) { Pass $c[0] } else { Fail $c[0] "got: $got" }
    }

    # === cases 15-20: the PowerShell-host --batch path against a mocked HTTP layer ===
    # Step 1b on a PowerShell-only host runs validate_batch.py, then
    # ship.ps1 -CheckPayload; Step 9 runs ship.ps1 -Batch. Each runs as a child
    # process here; the "Stride API" is a raw TcpListener on 127.0.0.1 that
    # answers one request with a canned 201.
    $pluginRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $shipPs1 = Join-Path $pluginRoot 'lib/ship.ps1'
    $validator = Join-Path $pluginRoot 'lib/validate_batch.py'
    $pythonExe = if (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { 'python' }
    $pwshExe = (Get-Process -Id $PID).Path
    $token = 'stride_dev_PREVIEW_PS_TOKEN_7x2q'
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $script:Pending = $null
    $port = $listener.LocalEndpoint.Port
    $auth = Join-Path $tmpDir 'auth.md'
    [System.IO.File]::WriteAllText($auth, "- **API URL:** ``http://127.0.0.1:$port```n- **API Token:** ``$token```n")
    $created = '{"success": true, "total": 1, "goals": [{"goal": {"id": 1, "identifier": "G77", "title": "Goal", "type": "goal"}, "child_tasks": [{"id": 2, "identifier": "W901", "title": "Task"}]}]}'
    $shipBatch = Join-Path $tmpDir 'declined-stride-batch.json'
    Copy-Item -LiteralPath (Join-Path $pluginRoot 'fixtures/2026-05-12T120000-dark-mode-toggle-stride-batch.json') -Destination $shipBatch

    # Invoke-Child <exe> <args> — runs a child process with STRIDE_AUTH_FILE set,
    # answering at most one request. Sets $script:CRc, COut, CErr, CRequests.
    function Invoke-Child([string]$Exe, [string[]]$ChildArgs) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = (@($ChildArgs | ForEach-Object { '"' + $_ + '"' })) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['STRIDE_AUTH_FILE'] = $auth
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $script:CRequests = 0
        # One accept is kept pending across children: a fresh accept per child
        # would leave the previous one waiting, and it would swallow the next
        # connection without answering it.
        if (-not $script:Pending) { $script:Pending = $listener.AcceptTcpClientAsync() }
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while (-not $p.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            if ($script:Pending.Wait(100)) {
                $script:CRequests++
                $conn = $script:Pending.Result
                $script:Pending = $listener.AcceptTcpClientAsync()
                $stream = $conn.GetStream()
                $buf = New-Object byte[] 65536
                $seen = ''
                # Read until the declared body has arrived (headers + Content-Length).
                while ($true) {
                    $n = $stream.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $seen += [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
                    $he = $seen.IndexOf("`r`n`r`n")
                    if ($he -ge 0) {
                        $m = [regex]::Match($seen.Substring(0, $he), '(?i)content-length:\s*(\d+)')
                        $want = if ($m.Success) { [int]$m.Groups[1].Value } else { 0 }
                        if ([System.Text.Encoding]::UTF8.GetByteCount($seen.Substring($he + 4)) -ge $want) { break }
                    }
                }
                $body = [System.Text.Encoding]::UTF8.GetBytes($created)
                $head = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 201 Created`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n")
                $stream.Write($head, 0, $head.Length)
                $stream.Write($body, 0, $body.Length)
                $stream.Flush()
                $conn.Close()
            }
        }
        if (-not $p.HasExited) { $p.Kill(); $script:CRequests = -1 }
        $p.WaitForExit()
        $script:CRc = $p.ExitCode
        $script:COut = $outTask.Result
        $script:CErr = $errTask.Result
    }

    $shaBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $shipBatch).Hash
    Invoke-Child $pythonExe @($validator, $shipBatch)
    $vRc = $CRc; $vReq = $CRequests
    Invoke-Child $pwshExe @('-NoProfile', '-NonInteractive', '-File', $shipPs1, '-CheckPayload', $shipBatch)
    if ($vRc -eq 0 -and $vReq -eq 0 -and $CRc -eq 0 -and $CRequests -eq 0) {
        Pass 'case 15: Step 1b (PowerShell) validates and token-screens a valid batch without a request'
    } else {
        Fail 'case 15: Step 1b (PowerShell) on a valid batch' "validate rc=$vRc check rc=$CRc requests=$CRequests err=$CErr"
    }
    Invoke-Child $pwshExe @('-NoProfile', '-NonInteractive', '-File', $shipPs1, '-Batch', $shipBatch)
    if ($CRc -eq 0 -and $CRequests -eq 1 -and $COut.Contains('G77') -and $COut.Contains('W901')) {
        Pass 'case 16: Step 9 (PowerShell) ships the --batch file once through ship.ps1 and renders the identifiers'
    } else {
        Fail 'case 16: Step 9 (PowerShell) ship' "rc=$CRc requests=$CRequests out=$COut err=$CErr"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $shipBatch).Hash -eq $shaBefore) {
        Pass 'case 17: the --batch file is byte-identical after shipping'
    } else {
        Fail 'case 17: the --batch file was rewritten'
    }

    $bad = Get-Content -Raw -LiteralPath $shipBatch | ConvertFrom-Json
    $bad.goals[0].tasks[0].PSObject.Properties.Remove('type')
    $badPath = Join-Path $tmpDir 'bad-stride-batch.json'
    [System.IO.File]::WriteAllText($badPath, ($bad | ConvertTo-Json -Depth 20))
    Invoke-Child $pythonExe @($validator, $badPath)
    if ($CRc -eq 1 -and $CRequests -eq 0 -and $CErr.Contains("goals[0].tasks[0] is missing required field 'type'")) {
        Pass 'case 18: an invalid batch fails validation before any request'
    } else {
        Fail 'case 18: invalid batch' "rc=$CRc requests=$CRequests err=$CErr"
    }

    $tok = Get-Content -Raw -LiteralPath $shipBatch | ConvertFrom-Json
    $tok.decomposition_notes = "pasted: $token"
    $tokPath = Join-Path $tmpDir 'token-stride-batch.json'
    [System.IO.File]::WriteAllText($tokPath, ($tok | ConvertTo-Json -Depth 20))
    Invoke-Child $pwshExe @('-NoProfile', '-NonInteractive', '-File', $shipPs1, '-CheckPayload', $tokPath)
    if ($CRc -eq 1 -and $CRequests -eq 0 -and $CErr.Contains('contains the configured Stride API token') -and -not ("$COut$CErr").Contains($token)) {
        Pass 'case 19: a batch carrying the API token is refused by -CheckPayload without printing it'
    } else {
        Fail 'case 19: token batch' "rc=$CRc requests=$CRequests"
    }

    Invoke-Child $pwshExe @('-NoProfile', '-NonInteractive', '-File', $shipPs1, '-CheckPayload', (Join-Path $tmpDir 'nope-stride-batch.json'))
    if ($CRc -eq 1 -and $CErr.Contains('batch JSON not found at')) {
        Pass 'case 20: a missing batch path stops -CheckPayload'
    } else {
        Fail 'case 20: missing batch path' "rc=$CRc err=$CErr"
    }
    $listener.Stop()
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
