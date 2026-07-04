# PowerShell mirror of test-validate-batch.sh — exercises validate_batch.py
# against known-good and known-broken JSON inputs.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginRoot = Split-Path -Parent $ScriptDir
$Validator = Join-Path $ScriptDir 'validate_batch.py'

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-validate-batch.ps1 — exercises validate_batch.py'
Write-Host ''

function Invoke-Validator([string]$JsonText) {
    $tmp = New-TemporaryFile
    Set-Content -LiteralPath $tmp.FullName -Value $JsonText -Encoding UTF8
    $errFile = New-TemporaryFile
    $outText = (& python3 $Validator $tmp.FullName 2>$errFile.FullName | Out-String)
    $rc = $LASTEXITCODE
    $errText = Get-Content -Raw -LiteralPath $errFile.FullName -ErrorAction SilentlyContinue
    Remove-Item -Force $tmp.FullName, $errFile.FullName -ErrorAction SilentlyContinue
    return @{ rc = $rc; stdout = $outText; stderr = $errText }
}

# Stage 1: a well-formed minimal batch passes.
$ok = @'
{"goals": [{"title": "Test goal", "type": "goal", "tasks": [{"title": "T1", "type": "work"}]}]}
'@
$r = Invoke-Validator $ok
if ($r.rc -eq 0) { Pass "well-formed batch accepted" } else { Fail "well-formed batch rejected" $r.stderr }

# Stage 2: malformed JSON triggers parse_error.
$r = Invoke-Validator 'not json at all {{'
if ($r.rc -ne 0 -and ($r.stderr -match 'parse|JSON')) { Pass "parse_error reported on bad JSON" } else { Fail "parse_error not detected" $r.stderr }

# Stage 3: wrong root key (tasks instead of goals) reports the common mistake.
$wrongRoot = '{"tasks": [{"title": "x", "type": "work"}]}'
$r = Invoke-Validator $wrongRoot
if ($r.rc -ne 0 -and ($r.stderr -match "(?i)root.*key|tasks|goals")) {
    Pass "wrong_root_key detected"
} else {
    Fail "wrong_root_key not detected" $r.stderr
}

# Stage 4: empty goals array.
$r = Invoke-Validator '{"goals": []}'
if ($r.rc -ne 0 -and ($r.stderr -match "empty|goals")) { Pass "empty_goals detected" } else { Fail "empty_goals not detected" $r.stderr }

# Stage 5: goal missing required field (title).
$missingField = '{"goals": [{"type": "goal", "tasks": []}]}'
$r = Invoke-Validator $missingField
if ($r.rc -ne 0 -and ($r.stderr -match "title|required|missing")) {
    Pass "goal_missing_field detected"
} else {
    Fail "goal_missing_field not detected" $r.stderr
}

# Stage 6: bad dependency index (forward reference).
$badDep = @'
{"goals": [{"title": "G", "type": "goal", "tasks": [
    {"title": "T1", "type": "work", "dependencies": [5]}
]}]}
'@
$r = Invoke-Validator $badDep
if ($r.rc -ne 0 -and ($r.stderr -match "dependency|dependencies|index|references")) {
    Pass "bad_dependency_index detected"
} else {
    Fail "bad_dependency_index not detected" $r.stderr
}

# Stage 7: (f) length_limit — a 256-code-point task title is fatal and names its path.
$longTitle = 'x' * 256
$len256 = '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "' + $longTitle + '", "type": "work", "dependencies": []}]}]}'
$r = Invoke-Validator $len256
if ($r.rc -ne 0 -and ($r.stderr -match 'title is 256 characters')) {
    Pass "(f) 256-char task title fails as a length_limit violation"
} else {
    Fail "(f) length_limit not detected on a 256-char title" $r.stderr
}

# Stage 8: (f) boundary — exactly 255 code points passes (limit is inclusive).
$title255 = 'x' * 255
$len255 = '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "' + $title255 + '", "type": "work", "dependencies": [], "acceptance_criteria": "ok", "testing_strategy": {"unit_tests": ["u"]}, "security_considerations": ["none"], "pitfalls": ["none"], "patterns_to_follow": "p"}]}]}'
$r = Invoke-Validator $len255
if ($r.rc -eq 0) { Pass "(f) boundary: exactly 255 characters passes" } else { Fail "(f) 255-char title wrongly rejected" $r.stderr }

# Stage 9: (f) an oversized security_considerations element is flagged with its element path.
$longElem = 'y' * 271
$lenSec = '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work", "dependencies": [], "security_considerations": ["fine", "' + $longElem + '"]}]}]}'
$r = Invoke-Validator $lenSec
if ($r.rc -ne 0 -and ($r.stderr -match 'security_considerations\[1\] is 271 characters')) {
    Pass "(f) oversized security_considerations element names its element path"
} else {
    Fail "(f) length_limit not detected on a security_considerations element" $r.stderr
}

# Stage 10: advisory — a task missing a scored field WARNS on stdout but still exits 0.
$warnMissing = '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work", "dependencies": []}]}]}'
$r = Invoke-Validator $warnMissing
if ($r.rc -eq 0 -and [string]::IsNullOrEmpty($r.stderr) -and ($r.stdout -match 'warning:.*is empty or missing')) {
    Pass "advisory: missing scored field warns on stdout but validation passes (exit 0)"
} else {
    Fail "advisory scored-field warning not emitted on stdout with exit 0" ("rc={0} stderr={1} stdout={2}" -f $r.rc, $r.stderr, $r.stdout)
}

# Stage 11: advisory — a fully populated task produces NO output at all.
$silent = '{"goals": [{"title": "G", "type": "goal", "tasks": [{"title": "T", "type": "work", "dependencies": [], "acceptance_criteria": "ok", "testing_strategy": {"unit_tests": ["u"]}, "security_considerations": ["none"], "pitfalls": ["none"], "patterns_to_follow": "p"}]}]}'
$r = Invoke-Validator $silent
if ($r.rc -eq 0 -and [string]::IsNullOrEmpty($r.stderr) -and [string]::IsNullOrWhiteSpace($r.stdout)) {
    Pass "advisory: all five scored fields populated — validator is completely silent"
} else {
    Fail "fully-populated task should be silent" ("rc={0} stderr={1} stdout={2}" -f $r.rc, $r.stderr, $r.stdout)
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
