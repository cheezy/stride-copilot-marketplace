# PowerShell mirror of test-all.sh — top-level smoke-test runner for the
# stride-copilot-exploratory-testing plugin.
#
# Runs every lib/test-*.ps1 check (structure + frontmatter) and aggregates the
# result. No network, no jq. Use this as the single entry point to gate a
# release on Windows:
#
#   pwsh -File lib/test-all.ps1
#
# Exit code: 0 only if every sub-script passes; 1 if any sub-script fails.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$tests = @('test-structure.ps1', 'test-frontmatter.ps1')

$ran = 0
$failed = 0

foreach ($t in $tests) {
    Write-Host "=== $t ==="
    $ran++
    & (Join-Path $ScriptDir $t)
    if ($LASTEXITCODE -ne 0) { $failed++ }
    Write-Host ''
}

Write-Host '================================'
if ($failed -gt 0) {
    Write-Host ("{0} of {1} smoke-test script(s) FAILED" -f $failed, $ran)
    exit 1
}
Write-Host ("All {0} smoke-test scripts passed" -f $ran)
exit 0
