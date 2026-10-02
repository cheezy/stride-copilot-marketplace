# PowerShell mirror of test-stridify-per-goal.sh — exercises the
# Sti-ResolveGoal, Sti-ExtractSeams, and Sti-ScopeDocToSeam cmdlets that
# the stride-ideation-stridify skill's --goal flow depends on.

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'filename.ps1')

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-stridify-per-goal.ps1 — exercises Sti-ResolveGoal + Sti-ExtractSeams + Sti-ScopeDocToSeam'
Write-Host ''

# Build a synthetic requirements doc with a Decomposition seams section.
$tmp = New-TemporaryFile
$docPath = "$($tmp.FullName).md"
Move-Item -LiteralPath $tmp.FullName -Destination $docPath
Set-Content -LiteralPath $docPath -Encoding UTF8 -Value @'
# Test doc

## Goal
A goal.

## Decomposition seams

The surfaces:

1. **Kanban app** — owns the JSON contract for the workflow
2. **stride plugin** — adapter for the Claude reference workflow
3. **stride-copilot** — adapter for GitHub Copilot

Shared notes:
- All three surfaces ship independently
- Coordination via SemVer

## Other section
Unaffected.
'@

try {
    # Stage 1: Sti-ExtractSeams emits 3 tuples in order.
    $seams = @(Sti-ExtractSeams -Path $docPath)
    if ($LASTEXITCODE -eq 0 -and $seams.Count -eq 3) {
        Pass "Sti-ExtractSeams emits 3 tuples"
    } else {
        Fail "Sti-ExtractSeams unexpected count" "rc=$LASTEXITCODE count=$($seams.Count)"
    }

    if ($seams.Count -ge 1 -and ($seams[0] -split "`t")[0] -eq '1') { Pass "first tuple has index 1" } else { Fail "first tuple index wrong" }
    if ($seams.Count -ge 1 -and ($seams[0] -split "`t")[2] -ceq 'kanban-app') { Pass "first tuple slug is 'kanban-app'" } else { Fail "first tuple slug wrong" "[$($seams[0])]" }
    if ($seams.Count -ge 3 -and ($seams[2] -split "`t")[2] -ceq 'stride-copilot') { Pass "third tuple slug is 'stride-copilot'" } else { Fail "third tuple slug wrong" }

    # Stage 2: Sti-ResolveGoal with digit input resolves by index.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg '2'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[1] -ceq 'stride plugin') {
        Pass "digit '2' resolves to second seam"
    } else {
        Fail "digit resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 3: Sti-ResolveGoal with slug input resolves by slug.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg 'stride-copilot'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[0] -eq '3') {
        Pass "slug 'stride-copilot' resolves to index 3"
    } else {
        Fail "slug resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 4: Sti-ResolveGoal with name input (will slugify) resolves.
    $r = Sti-ResolveGoal -Path $docPath -GoalArg 'Kanban app'
    if ($LASTEXITCODE -eq 0 -and ($r -split "`t")[0] -eq '1') {
        Pass "name 'Kanban app' resolves via slugify"
    } else {
        Fail "name slugify resolution failed" "rc=$LASTEXITCODE r=[$r]"
    }

    # Stage 5: No-match returns rc=3.
    $null = Sti-ResolveGoal -Path $docPath -GoalArg 'nonexistent'
    if ($LASTEXITCODE -eq 3) { Pass "no-match returns rc=3" } else { Fail "no-match should return 3" "rc=$LASTEXITCODE" }

    # Stage 6: Sti-ScopeDocToSeam keeps only the matched item in the seams section.
    $scoped = @(Sti-ScopeDocToSeam -Path $docPath -Target 2)
    $scopedText = $scoped -join "`n"
    if ($scopedText -match 'Scoped to a single surface') { Pass "scoped doc has scoped-notice line" } else { Fail "scoped notice missing" }
    if ($scopedText -match 'stride plugin') { Pass "scoped doc retains item 2" } else { Fail "scoped doc dropped target item" }
    # Other items should be absent.
    if ($scopedText -notmatch 'Kanban app' -and $scopedText -notmatch 'stride-copilot') {
        Pass "scoped doc drops non-target items"
    } else {
        Fail "scoped doc retained non-target items"
    }
    # Other sections preserved.
    if ($scopedText -match 'Other section') { Pass "scoped doc preserves other sections" } else { Fail "scoped doc dropped other sections" }

    # Stage 7: doc without Decomposition seams -> Sti-ExtractSeams rc=2.
    $noSeams = "$($docPath).noseams.md"
    Set-Content -LiteralPath $noSeams -Encoding UTF8 -Value "# foo`n## Goal`nA"
    $null = Sti-ExtractSeams -Path $noSeams
    if ($LASTEXITCODE -eq 2) { Pass "Sti-ExtractSeams returns rc=2 when section absent" } else { Fail "section-absent should return rc=2" "rc=$LASTEXITCODE" }
    Remove-Item -Force $noSeams -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Force $docPath -ErrorAction SilentlyContinue
}

# === cases 16-24: one seam definition for count, resolve and scope (D327) ===
$TMP = Join-Path ([System.IO.Path]::GetTempPath()) ('sti-seams-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TMP | Out-Null
try {
    function New-SeamsDoc([string]$Name, [string]$Body) {
        $f = Join-Path $TMP $Name
        $text = "# Doc`n`n## Problem`n`np`n`n## Decomposition seams`n`nIntro prose.`n`n" + $Body + "`n## Assumptions`n`na`n"
        [System.IO.File]::WriteAllText($f, $text)
        return $f
    }
    function Get-SeamNames([string]$f) { ((@(Sti-ExtractSeams -Path $f) | ForEach-Object { ($_ -split "`t")[1] }) -join '|') + '|' }
    function Get-SeamCount([string]$f) { @(Sti-ExtractSeams -Path $f).Count }
    # The Step 2 advisory's count, computed exactly as the stridify skill's Step 2 block does.
    function Get-AdvisoryCount([string]$f) { @(Sti-ExtractSeams -Path $f).Count }
    function Get-Field([string]$tuple, [int]$n) { if ($tuple) { ($tuple -split "`t")[$n] } else { '' } }

    $bulleted = New-SeamsDoc 'bulleted.md' @"
- **Kanban app** — owns the JSON contract
- **stride plugin** — adapter
  - nested note that is not a seam
- **stride-copilot** — port
* **Docs site** — guides

"@
    if (((Get-SeamCount $bulleted) -eq 4) -and ((Get-SeamNames $bulleted) -ceq 'Kanban app|stride plugin|stride-copilot|Docs site|')) {
        Pass 'case 16a: four bulleted bold seams are extracted (nested bullets are not seams)'
    } else { Fail 'case 16a: bulleted extraction' "count=$(Get-SeamCount $bulleted) names=$(Get-SeamNames $bulleted)" }
    $case16ok = $true
    foreach ($i in 1..4) { Sti-ResolveGoal -Path $bulleted -GoalArg "$i" | Out-Null; if ($LASTEXITCODE -ne 0) { $case16ok = $false } }
    if ($case16ok -and ((Get-AdvisoryCount $bulleted) -eq 4)) { Pass 'case 16b: the advisory counts 4 and --goal 1..4 all resolve (rc 0)' }
    else { Fail 'case 16b: advisory and resolver disagree on bulleted seams' }
    $scoped16 = @(Sti-ScopeDocToSeam -Path $bulleted -Target 2)
    if (($scoped16 -contains '- **stride plugin** — adapter') -and ($scoped16 -contains '  - nested note that is not a seam') -and
        -not ($scoped16 | Where-Object { $_ -match '\*\*(Kanban app|stride-copilot|Docs site)\*\*' }) -and
        ($scoped16 | Where-Object { $_ -match '^## Assumptions' })) {
        Pass 'case 16c: scoping a bulleted doc to item 2 keeps only that item (with its nested lines)'
    } else { Fail 'case 16c: bulleted scoping' ($scoped16 -join ' / ') }

    $headings = New-SeamsDoc 'headings.md' @"
### Kanban app

Owns the JSON contract.

#### Detail that stays with the item

### stride plugin

Adapter.

"@
    if ((Get-SeamNames $headings) -ceq 'Kanban app|stride plugin|') { Pass 'case 17a: ### headings are seams when there are no bold items (#### is not)' }
    else { Fail 'case 17a: heading extraction' "names=$(Get-SeamNames $headings)" }
    $case17idx = Get-Field (Sti-ResolveGoal -Path $headings -GoalArg '2') 1
    $case17slug = Get-Field (Sti-ResolveGoal -Path $headings -GoalArg 'kanban-app') 0
    if (($case17idx -ceq 'stride plugin') -and ($case17slug -eq '1')) { Pass 'case 17b: heading seams resolve by index and by slug' }
    else { Fail 'case 17b: heading resolution' "idx2=$case17idx slug->$case17slug" }
    $scoped17 = @(Sti-ScopeDocToSeam -Path $headings -Target 1)
    if (($scoped17 -contains '#### Detail that stays with the item') -and -not ($scoped17 -contains '### stride plugin')) {
        Pass 'case 17c: scoping a heading doc keeps the item and its sub-headings only'
    } else { Fail 'case 17c: heading scoping' ($scoped17 -join ' / ') }

    $mixed = New-SeamsDoc 'mixed.md' @"
1. **Kanban app** — contract
2. **stride plugin** — adapter
3. **stride-copilot** — port

Shared contract:
- **JSON schema** — cross-cutting
- **Auth** — cross-cutting
- **Versioning** — cross-cutting
- **Telemetry** — cross-cutting
- **Docs** — cross-cutting

"@
    if (((Get-AdvisoryCount $mixed) -eq 3) -and ((Get-SeamNames $mixed) -ceq 'Kanban app|stride plugin|stride-copilot|')) {
        Pass "case 18: a numbered list's secondary bullets are not counted as seams (advisory stays quiet at 3)"
    } else { Fail 'case 18: mixed numbered + bullets' "count=$(Get-AdvisoryCount $mixed) names=$(Get-SeamNames $mixed)" }

    $dashName = New-SeamsDoc 'dash-name.md' @"
- **front-end — web** — the UI
- **back-end** — the API

"@
    if ((Get-Field (Sti-ResolveGoal -Path $dashName -GoalArg '1') 1) -ceq 'front-end — web') { Pass 'case 19: a bold name containing dashes is kept verbatim' }
    else { Fail 'case 19: dashed name' (Sti-ResolveGoal -Path $dashName -GoalArg '1') }

    $emptySection = New-SeamsDoc 'empty-section.md' ''
    Sti-ResolveGoal -Path $emptySection -GoalArg '1' | Out-Null
    $case20rc = $LASTEXITCODE
    if (($case20rc -eq 4) -and ((Get-AdvisoryCount $emptySection) -eq 0)) { Pass 'case 20: an empty seams section counts 0 and resolves rc 4 (contract unchanged)' }
    else { Fail 'case 20: empty section' "rc=$case20rc" }

    $skew = New-SeamsDoc 'skew.md' @"
1. **???** — not addressable
2. **Real** — the only real surface

"@
    $case21name = Get-Field (Sti-ResolveGoal -Path $skew -GoalArg '1') 1
    $scoped21 = @(Sti-ScopeDocToSeam -Path $skew -Target 1)
    if (($case21name -ceq 'Real') -and ($scoped21 | Where-Object { $_.Contains('2. **Real**') }) -and -not ($scoped21 | Where-Object { $_.Contains('**???**') })) {
        Pass "case 21: scoping uses the resolver's index (an unaddressable item does not shift it)"
    } else { Fail 'case 21: index skew' "resolved=$case21name scoped=$($scoped21 -join ' / ')" }

    $nestedSteps = New-SeamsDoc 'nested-steps.md' @"
- **Kanban app** — owns the contract
    1. **Schema** — a step, not a seam
    2. **Migration** — a step, not a seam
- **stride plugin** — adapter

"@
    Sti-ResolveGoal -Path $nestedSteps -GoalArg 'stride plugin' | Out-Null
    if (((Get-SeamNames $nestedSteps) -ceq 'Kanban app|stride plugin|') -and ($LASTEXITCODE -eq 0)) {
        Pass 'case 23: a nested numbered sub-list under bulleted seams does not take over the section'
    } else { Fail 'case 23: nested numbered steps' "names=$(Get-SeamNames $nestedSteps)" }

    # --- case 23b-e: the top-level anchor (0-3 leading spaces) -------------
    $threeSpace = New-SeamsDoc 'three-space.md' "   1. **Alpha** - three leading spaces is still a top-level item`n   2. **Beta** - likewise`n"
    if ((Get-SeamNames $threeSpace) -ceq 'Alpha|Beta|') { Pass 'case 23b: numbered seams indented by exactly 3 spaces still count' }
    else { Fail 'case 23b: 3-space numbered items' "names=$(Get-SeamNames $threeSpace)" }
    $fourSpace = New-SeamsDoc 'four-space.md' "    1. **Alpha** - four spaces is nested, never a seam`n    2. **Beta** - likewise`n"
    Sti-ResolveGoal -Path $fourSpace -GoalArg '1' | Out-Null
    $rc23c = $LASTEXITCODE
    if (((Get-SeamCount $fourSpace) -eq 0) -and ($rc23c -eq 4)) { Pass 'case 23c: numbered items indented by 4 spaces are not seams (count 0, resolve rc 4)' }
    else { Fail 'case 23c: 4-space numbered items' "count=$(Get-SeamCount $fourSpace) rc=$rc23c" }
    $tabSteps = New-SeamsDoc 'tab-steps.md' "- **Kanban app** - contract`n`t1. **Schema** - a tab-indented step`n- **stride plugin** - adapter`n"
    if ((Get-SeamNames $tabSteps) -ceq 'Kanban app|stride plugin|') { Pass 'case 23d: a tab-indented numbered sub-list under bulleted seams is ignored' }
    else { Fail 'case 23d: tab-indented sub-list' "names=$(Get-SeamNames $tabSteps)" }

    # --- case 24: numeric --goal and a case-sensitive heading, as in bash -----
    $r01 = Sti-ResolveGoal -Path $bulleted -GoalArg '01'
    $r1 = Sti-ResolveGoal -Path $bulleted -GoalArg '1'
    if ($r01 -and ($r01 -ceq $r1)) { Pass 'case 24a: --goal 01 resolves to the same seam as --goal 1' }
    else { Fail 'case 24a: --goal 01' "01=[$r01] 1=[$r1]" }
    $titleCase = Join-Path $TMP 'titlecase.md'
    [System.IO.File]::WriteAllText($titleCase, ([System.IO.File]::ReadAllText($bulleted) -creplace '(?m)^## Decomposition seams$', '## Decomposition Seams'))
    Sti-ResolveGoal -Path $titleCase -GoalArg '1' | Out-Null
    $rc24b = $LASTEXITCODE
    if (($rc24b -eq 2) -and ((Get-SeamCount $titleCase) -eq 0)) { Pass "case 24b: a '## Decomposition Seams' heading is not the seams section (case-sensitive, rc 2)" }
    else { Fail 'case 24b: title-case heading' "rc=$rc24b" }

    $case22ok = $true
    foreach ($doc in @($bulleted, $headings, $mixed, $dashName)) {
        foreach ($tuple in @(Sti-ExtractSeams -Path $doc)) {
            $parts = $tuple -split "`t"
            $text = (@(Sti-ScopeDocToSeam -Path $doc -Target ([int]$parts[0])) -join "`n")
            if (-not $text.Contains($parts[1])) { $case22ok = $false; Fail "case 22: $(Split-Path -Leaf $doc) index $($parts[0]) does not scope to '$($parts[1])'" }
        }
    }
    if ($case22ok) { Pass 'case 22: for every shape, each extracted index scopes to the seam it names' }
} finally {
    Remove-Item -Recurse -Force $TMP -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
