# PowerShell mirror of test-draft.sh — unit tests for lib/draft.ps1, the
# stride-ideation-ideate intra-session draft autosave/resume helpers (W1145).
#
# Run:
#   pwsh -File lib/test-draft.ps1
#
# Exits 0 if all tests pass, non-zero otherwise.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'draft.ps1')

$script:PASS = 0
$script:FAIL = 0
function Pass([string]$msg) { $script:PASS++; Write-Host "  PASS  $msg" }
function Fail([string]$msg, [string]$detail = '') {
    $script:FAIL++
    Write-Host "  FAIL  $msg"
    if ($detail) { Write-Host "        $detail" }
}
function Assert-Equal([string]$name, [string]$expected, [string]$actual) {
    if ($expected -ceq $actual) { Pass $name } else { Fail $name "expected=[$expected] actual=[$actual]" }
}

Write-Host 'test-draft.ps1 — exercises Sti-DraftPath/Find/Save/Load/Exists/Clear'
Write-Host ''

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "sti-draft-test-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    # --- draft_path: deterministic for a given ts+slug --------------------
    Assert-Equal 'draft_path: <dir>/<ts>-<slug>-draft.md' `
        '.stride/2026-05-12T103000-add-notifications-draft.md' `
        (Sti-DraftPath .stride 2026-05-12T103000 add-notifications)

    Assert-Equal 'draft_path: trailing slash on dir is normalized' `
        '.stride/2026-05-12T103000-foo-draft.md' `
        (Sti-DraftPath .stride/ 2026-05-12T103000 foo)

    $p1 = Sti-DraftPath $tmpDir 2026-05-12T103000 foo
    $p2 = Sti-DraftPath $tmpDir 2026-05-12T103000 foo
    Assert-Equal 'draft_path: deterministic for a given SESSION_TS+slug' $p1 $p2

    $bad = Sti-DraftPath $tmpDir 2026-05-12T103000 '' 2>$null
    if ([string]::IsNullOrEmpty($bad)) { Pass 'draft_path: missing slug -> empty stdout + error' }
    else { Fail 'draft_path: missing slug leaked output' "[$bad]" }

    # --- save then load: round-trips content ------------------------------
    $draft = Sti-DraftPath (Join-Path $tmpDir '.stride') 2026-05-12T103000 round-trip
    $content = "## Goal`nShip the digest.`n`n## Problem`nApprovals rot in inboxes.`n__round_state__: 2"

    Sti-DraftSave $draft $content 2>$null
    if ($LASTEXITCODE -eq 0) { Pass 'draft_save: writes the scratch file (and creates .stride/ parent)' }
    else { Fail 'draft_save: failed to write' "rc=$LASTEXITCODE" }

    if (Test-Path -LiteralPath $draft) { Pass 'draft_save: scratch file exists at the computed path' }
    else { Fail 'draft_save: scratch file missing after save' }

    Assert-Equal 'draft_load: round-trips the saved content byte-for-byte' $content (Sti-DraftLoad $draft)

    # --- exists: predicate on non-empty draft -----------------------------
    if (Sti-DraftExists $draft) { Pass 'draft_exists: true for a non-empty draft' }
    else { Fail 'draft_exists: false for a non-empty draft (should be true)' }

    $empty = Sti-DraftPath (Join-Path $tmpDir '.stride') 2026-05-12T103000 empty-draft
    New-Item -ItemType File -Path $empty -Force | Out-Null
    if (Sti-DraftExists $empty) { Fail 'draft_exists: true for an empty draft (should be false)' }
    else { Pass 'draft_exists: false for an empty/zero-length draft (partial -> fresh)' }

    if (Sti-DraftExists (Join-Path $tmpDir '.stride/nope-draft.md')) { Fail 'draft_exists: true for an absent draft (should be false)' }
    else { Pass 'draft_exists: false for an absent draft' }

    # --- load: absent file -> error, no crash -----------------------------
    $loadBad = Sti-DraftLoad (Join-Path $tmpDir '.stride/missing-draft.md') 2>$null
    if ([string]::IsNullOrEmpty($loadBad)) { Pass 'draft_load: absent file -> empty stdout + error (safe, no crash)' }
    else { Fail 'draft_load: absent file leaked output' "[$loadBad]" }

    # --- save: write-failure branch returns non-zero, no crash ------------
    $blocker = Join-Path $tmpDir 'blocker'
    New-Item -ItemType File -Path $blocker -Force | Out-Null
    $blockedDraft = "$blocker/sub/2026-05-12T103000-x-draft.md"
    $saveErr = (Sti-DraftSave $blockedDraft 'body' 2>&1 | Out-String)
    Sti-DraftSave $blockedDraft 'body' 2>$null
    if ($LASTEXITCODE -ne 0) { Pass 'draft_save: returns non-zero when the parent dir cannot be created (no crash)' }
    else { Fail 'draft_save: succeeded despite an unmakeable parent dir (should fail)' }
    if ($saveErr -match 'cannot write scratch draft') { Pass 'draft_save: write failure emits a diagnostic to stderr' }
    else { Fail 'draft_save: write failure produced no diagnostic' "[$saveErr]" }

    # --- clear: removes the scratch file (idempotent) ---------------------
    Sti-DraftClear $draft
    if (Test-Path -LiteralPath $draft) { Fail 'draft_clear: scratch file still present after clear' }
    else { Pass 'draft_clear: removes the scratch file' }
    Sti-DraftClear $draft
    if ($LASTEXITCODE -eq 0) { Pass 'draft_clear: idempotent (no error when already gone)' }
    else { Fail 'draft_clear: errored on an already-absent file' "rc=$LASTEXITCODE" }

    # --- find: resume detection matches only the same slug ----------------
    $fdir = Join-Path $tmpDir 'find-stride'
    New-Item -ItemType Directory -Path $fdir | Out-Null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T100000 alpha) 'alpha draft body' 2>$null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T110000 beta)  'beta draft body'  2>$null
    New-Item -ItemType File -Path (Sti-DraftPath $fdir 2026-05-12T120000 gamma) -Force | Out-Null  # empty -> ignored

    Assert-Equal 'draft_find: returns the matching-slug draft only (two slugs in flight)' `
        "$fdir/2026-05-12T100000-alpha-draft.md" `
        (Sti-DraftFind $fdir alpha)

    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T130000 oauth) 'oauth body' 2>$null
    $noauth = Sti-DraftFind $fdir auth 2>$null
    if ([string]::IsNullOrEmpty($noauth)) { Pass "draft_find: slug 'auth' does not match 'oauth' (dash-delimited suffix)" }
    else { Fail 'draft_find: auth cross-matched a different slug' "[$noauth]" }

    $none = Sti-DraftFind $fdir does-not-exist 2>$null
    if ([string]::IsNullOrEmpty($none)) { Pass 'draft_find: no matching draft -> empty stdout + non-zero (fresh session)' }
    else { Fail 'draft_find: leaked output for a slug with no draft' "[$none]" }

    $emptyOnly = Sti-DraftFind $fdir gamma 2>$null
    if ([string]::IsNullOrEmpty($emptyOnly)) { Pass 'draft_find: an empty-only draft is not offered for resume (partial -> fresh)' }
    else { Fail 'draft_find: offered an empty draft for resume' "[$emptyOnly]" }

    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T090000 multi) 'older' 2>$null
    Sti-DraftSave (Sti-DraftPath $fdir 2026-05-12T140000 multi) 'newer' 2>$null
    Assert-Equal 'draft_find: latest ISO timestamp wins for a repeated slug' `
        "$fdir/2026-05-12T140000-multi-draft.md" `
        (Sti-DraftFind $fdir multi)

    $abs = Sti-DraftFind (Join-Path $tmpDir 'no-such-dir') anything 2>$null
    if ([string]::IsNullOrEmpty($abs)) { Pass 'draft_find: absent scratch dir -> empty stdout + non-zero (no crash)' }
    else { Fail 'draft_find: leaked output for an absent dir' "[$abs]" }

    # --- find: anchored on the timestamp, so a suffix slug never matches ----
    $adir = Join-Path $tmpDir 'anchor-stride'
    New-Item -ItemType Directory -Path $adir | Out-Null
    Sti-DraftSave (Sti-DraftPath $adir 2026-05-12T120000 user-auth) 'user-auth body' 2>$null
    $ua = Sti-DraftFind $adir auth 2>$null
    if ([string]::IsNullOrEmpty($ua)) { Pass "draft_find: slug 'auth' does not match a 'user-auth' draft (timestamp-anchored)" }
    else { Fail "draft_find: 'auth' matched another topic's draft" "[$ua]" }
    Assert-Equal "draft_find: slug 'user-auth' still finds its own draft" "$adir/2026-05-12T120000-user-auth-draft.md" (Sti-DraftFind $adir user-auth)
    Sti-DraftSave (Sti-DraftPath $adir 2026-05-12T110000 auth) 'auth body' 2>$null
    Assert-Equal "draft_find: with both present, 'auth' returns the auth draft even though user-auth is newer" "$adir/2026-05-12T110000-auth-draft.md" (Sti-DraftFind $adir auth)
    [System.IO.File]::WriteAllText((Join-Path $adir 'notes-auth-draft.md'), 'x')
    Assert-Equal 'draft_find: a non-timestamp prefix is never matched' "$adir/2026-05-12T110000-auth-draft.md" (Sti-DraftFind $adir auth)

    # --- save: content from the pipeline, verbatim -------------------------
    $sdir = Join-Path $tmpDir 'pipe-stride'
    $spath = Sti-DraftPath $sdir 2026-05-12T103000 piped
    $prose = "Line one with `"double`" and 'single' quotes`ncost: `$HOME `$(id) ``whoami`` stays literal`n`nlast line`n"
    $prose | Sti-DraftSave $spath
    Assert-Equal 'draft_save: reads a multi-line string from the pipeline verbatim' $prose ([System.IO.File]::ReadAllText($spath))
    @('first', 'second') | Sti-DraftSave $spath
    Assert-Equal 'draft_save: pipeline items are joined with a newline' "first`nsecond" ([System.IO.File]::ReadAllText($spath))
    Sti-DraftSave $spath 'argument form'
    Assert-Equal 'draft_save: the argument form still works' 'argument form' ([System.IO.File]::ReadAllText($spath))
    $epath = Sti-DraftPath $sdir 2026-05-12T103000 emptyin
    @() | Sti-DraftSave $epath
    if ((Test-Path -LiteralPath $epath) -and (Get-Item -LiteralPath $epath).Length -eq 0 -and $LASTEXITCODE -eq 0) { Pass 'draft_save: an empty pipeline writes an empty draft, which find never offers' }
    else { Fail 'draft_save: empty pipeline mishandled' }
    $ef = Sti-DraftFind $sdir emptyin 2>$null
    if ([string]::IsNullOrEmpty($ef)) { Pass 'draft_find: an empty pipeline draft is not offered for resume' } else { Fail 'draft_find: offered an empty draft' "[$ef]" }

    # --- save: the scratch dir ignores itself ------------------------------
    $gdir = Join-Path (Join-Path $tmpDir 'selfignore') '.stride'
    Sti-DraftSave (Sti-DraftPath $gdir 2026-05-12T103000 gi) 'body'
    Assert-Equal "draft_save: creating the scratch dir writes <dir>/.gitignore containing '*'" "*`n" ([System.IO.File]::ReadAllText((Join-Path $gdir '.gitignore')))
    [System.IO.File]::WriteAllText((Join-Path $gdir '.gitignore'), "custom`n")
    Sti-DraftSave (Sti-DraftPath $gdir 2026-05-12T103000 gi) 'body again'
    Assert-Equal 'draft_save: an existing .gitignore is never overwritten' "custom`n" ([System.IO.File]::ReadAllText((Join-Path $gdir '.gitignore')))
    $pre2 = Join-Path (Join-Path $tmpDir 'preexisting2') '.stride'
    New-Item -ItemType Directory -Path $pre2 -Force | Out-Null
    Sti-DraftSave (Sti-DraftPath $pre2 2026-05-12T103000 pre) 'body'
    Assert-Equal 'draft_save: an existing .stride dir without a .gitignore gets one' "*`n" ([System.IO.File]::ReadAllText((Join-Path $pre2 '.gitignore')))
    $plain = Join-Path $tmpDir 'plain-dir'
    New-Item -ItemType Directory -Path $plain | Out-Null
    Sti-DraftSave (Join-Path $plain '2026-05-12T103000-plain-draft.md') 'body'
    if (-not (Test-Path -LiteralPath (Join-Path $plain '.gitignore'))) { Pass 'draft_save: an existing directory not named .stride never gets a .gitignore' }
    else { Fail 'draft_save: wrote a .gitignore into an existing non-scratch directory' }

    $ddir = Join-Path (Join-Path $tmpDir 'dir-helper') '.stride'
    Sti-DraftDir $ddir
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $ddir -PathType Container) -and ([System.IO.File]::ReadAllText((Join-Path $ddir '.gitignore')) -ceq "*`n") -and @(Get-ChildItem -LiteralPath $ddir).Count -eq 0) { Pass 'draft_dir: creates the scratch dir and its self-ignore file, and no draft' }
    else { Fail 'draft_dir: did not create the scratch dir and .gitignore' }
    Sti-DraftDir '' 2>$null
    if ($LASTEXITCODE -ne 0) { Pass 'draft_dir: empty dir is a usage error' } else { Fail 'draft_dir: accepted an empty dir' }

    # --- save: no content and no pipeline is a usage error, not a wipe ------
    $keep = Sti-DraftPath (Join-Path $tmpDir 'noinput-stride') 2026-05-12T103000 keep
    Sti-DraftSave $keep 'saved answers'
    $noInputErr = (Sti-DraftSave $keep 2>&1 | Out-String)
    $rcNoInput = $LASTEXITCODE
    if ($rcNoInput -ne 0 -and $noInputErr -match 'Sti-DraftSave: usage' -and ([System.IO.File]::ReadAllText($keep) -ceq 'saved answers')) {
        Pass 'draft_save: no content and no pipeline is a usage error and leaves the draft intact'
    } else {
        Fail 'draft_save: no-input call did not fail cleanly' "rc=$rcNoInput content=[$([System.IO.File]::ReadAllText($keep))]"
    }

    # --- integration (git only, no bash): drafts never reach git status ------
    $grepo = Join-Path $tmpDir 'git-repo'
    New-Item -ItemType Directory -Path $grepo | Out-Null
    & git -C $grepo init -q
    Push-Location $grepo
    try { Sti-DraftSave (Sti-DraftPath .stride 2026-05-12T103000 repo) 'secret-ish ideation prose' } finally { Pop-Location }
    $status = @(& git -C $grepo status --porcelain --untracked-files=all)
    if ($status.Count -eq 0) { Pass 'draft_save: in a fresh repo, git status shows nothing under .stride/ after a save' }
    else { Fail 'draft_save: the draft shows up in git status' ($status -join ' ') }

    # A pre-existing .stride/.gitignore that does not cover drafts is kept, and
    # the drafts are still ignored (through the local .git/info/exclude).
    $crepo = Join-Path $tmpDir 'cache-repo'
    New-Item -ItemType Directory -Path (Join-Path $crepo '.stride') -Force | Out-Null
    & git -C $crepo init -q
    [System.IO.File]::WriteAllText((Join-Path $crepo '.stride/.gitignore'), "cache/`n")
    Push-Location $crepo
    try { Sti-DraftSave (Sti-DraftPath .stride 2026-05-12T103000 cached) 'prose' } finally { Pop-Location }
    $cstatus = @(& git -C $crepo status --porcelain --untracked-files=all)
    if (-not ($cstatus | Where-Object { $_ -match 'draft\.md' })) { Pass 'draft_dir: a .stride/.gitignore that does not cover drafts still leaves drafts ignored' }
    else { Fail 'draft_dir: a draft shows up in git status despite the existing .stride/.gitignore' ($cstatus -join ' ') }
    Assert-Equal 'draft_dir: the existing .stride/.gitignore is not modified' "cache/`n" ([System.IO.File]::ReadAllText((Join-Path $crepo '.stride/.gitignore')))

    # A rule that re-includes drafts makes the helper refuse instead of writing.
    $nrepo = Join-Path $tmpDir 'negate-repo'
    New-Item -ItemType Directory -Path (Join-Path $nrepo '.stride') -Force | Out-Null
    & git -C $nrepo init -q
    [System.IO.File]::WriteAllText((Join-Path $nrepo '.stride/.gitignore'), "!*-draft.md`n")
    Push-Location $nrepo
    try { $negErr = (Sti-DraftSave (Sti-DraftPath .stride 2026-05-12T103000 neg) 'prose' 2>&1 | Out-String); $negRc = $LASTEXITCODE } finally { Pop-Location }
    if ($negRc -ne 0 -and $negErr -match 'would not be ignored' -and -not (Test-Path -LiteralPath (Join-Path $nrepo '.stride/2026-05-12T103000-neg-draft.md'))) {
        Pass 'draft_save: refuses (non-zero, no draft written) when a .gitignore rule re-includes drafts'
    } else {
        Fail 'draft_save: wrote or accepted a draft git would not ignore' "rc=$negRc"
    }

    # --- cross-language checks (need bash; reported as skipped without it) --
    # Get-Command decides availability, never an exit code. On Windows,
    # System32\bash.exe is the WSL launcher, which cannot read Windows paths.
    $bashCmd = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bashCmd -and $bashCmd.Source -match '(?i)\\System32\\bash\.exe$') { $bashCmd = $null }
    if ($bashCmd) {
        # Byte-for-byte the same self-ignore file as lib/draft.sh writes.
        $shDir = Join-Path $tmpDir 'sh-stride/.stride'
        & $bashCmd.Source -c '. "$1"; sti_draft_save "$2/2026-05-12T103000-x-draft.md" body' _ (Join-Path $ScriptDir 'draft.sh') $shDir
        $fresh = Join-Path (Join-Path $tmpDir 'fresh') '.stride'
        Sti-DraftSave (Sti-DraftPath $fresh 2026-05-12T103000 f) 'b'
        $same = (Test-Path -LiteralPath (Join-Path $shDir '.gitignore')) -and [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes((Join-Path $shDir '.gitignore')), [byte[]][System.IO.File]::ReadAllBytes((Join-Path $fresh '.gitignore')))
        if ($same) { Pass 'draft_save: the .gitignore bytes match lib/draft.sh exactly' } else { Fail 'draft_save: .gitignore bytes differ from lib/draft.sh' }

        # Same files matched in both languages, in both directions.
        $both = Join-Path $tmpDir 'parity-stride'
        New-Item -ItemType Directory -Path $both | Out-Null
        foreach ($n in @('2026-05-12T100000-auth-draft.md', '2026-05-12T120000-user-auth-draft.md', 'notes-auth-draft.md', '2026-05-12-auth-draft.md', '2026-05-12T130000-oauth-draft.md')) {
            [System.IO.File]::WriteAllText((Join-Path $both $n), 'x')
        }
        foreach ($slug in @('auth', 'user-auth', 'oauth', 'nothing-here')) {
            $psFound = [string](Sti-DraftFind $both $slug)
            $shFound = [string](& $bashCmd.Source -c '. "$1"; sti_draft_find "$2" "$3"' _ (Join-Path $ScriptDir 'draft.sh') $both $slug)
            Assert-Equal "draft_find: bash and PowerShell pick the same draft for '$slug'" $shFound $psFound
        }
    } else {
        Pass 'draft_save: SKIPPED (no usable bash) - .gitignore byte comparison with lib/draft.sh'
        Pass 'draft_find: SKIPPED (no usable bash) - bash/PowerShell lookup parity'
    }
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
# --- dot-sourcing leaves the caller's strict mode alone -----------------------
# A skill step dot-sources this helper into its own session; a file-scope
# Set-StrictMode here would leak into it, and reading an unset optional
# variable such as $CONTINUE_PATH would then throw.
$probe = @'
Set-StrictMode -Off
. '__HELPER__'
try { $null = $CONTINUE_PATH; 'strict-off' } catch { 'strict-on' }
if (Sti-DraftPath .stride 2026-05-12T103000 foo) { 'ok' }
'@
$probe = $probe.Replace('__HELPER__', (Join-Path $ScriptDir 'draft.ps1'))
$pwshExe = (Get-Process -Id $PID).Path
$probeOut = (& $pwshExe -NoProfile -NonInteractive -Command $probe) -join ','
Assert-Equal "dot-sourcing draft.ps1 leaves strict mode off in the caller, and its functions still work" "strict-off,ok" $probeOut

Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
