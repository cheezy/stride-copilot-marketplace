# stride-ideation intra-session draft autosave helpers
# (PowerShell mirror of lib/draft.sh).
#
# Six pure cmdlets used by the stride-ideation-ideate skill to persist an
# in-progress ideation draft to a gitignored scratch file under .stride/, so an
# interruption mid-session is recoverable and a later session can offer resume.
# PascalCase-with-hyphen cmdlet names mirror the snake_case bash functions
# one-to-one:
#
#   sti_draft_path   -> Sti-DraftPath
#   sti_draft_find   -> Sti-DraftFind
#   sti_draft_save   -> Sti-DraftSave
#   sti_draft_dir    -> Sti-DraftDir
#   sti_draft_load   -> Sti-DraftLoad
#   sti_draft_exists -> Sti-DraftExists
#   sti_draft_clear  -> Sti-DraftClear
#
# Filename rule: the scratch path is <dir>/<ts>-<slug>-draft.md, pairing with
# the eventual requirements doc by its <ts>-<slug> prefix. The draft lives under
# a GITIGNORED .stride/ path so half-finished, possibly sensitive ideation is
# never committed; the helper never serializes any secret — it only writes the
# content it is handed.
#
# Resume keys on the SLUG, not the session timestamp: Sti-DraftFind matches
# every <ts>-<slug>-draft.md (any timestamp) and returns the latest (ISO
# timestamps sort lexically). The match is anchored on the full
# YYYY-MM-DDTHHMMSS prefix, so `auth` matches neither `oauth` nor `user-auth`
# — exactly the files lib/draft.sh matches.
#
# Sti-DraftSave takes its content as the second argument or from the pipeline
# (pipeline items are joined with "`n"), so prose never has to be quoted into
# a command line. When Sti-DraftDir (which Sti-DraftSave calls) creates the
# scratch dir — or is handed one named `.stride` — it also writes
# <dir>/.gitignore containing `*` if that file is
# absent, so drafts stay out of `git add -A` without touching the project's own
# .gitignore. An existing <dir>/.gitignore is never overwritten. Inside a git
# work tree it then checks that a draft name really is ignored; if not, it adds
# `/<dir>/*-draft.md` to the repository's local .git/info/exclude (never a
# tracked file), and if drafts are still not ignored it fails — exactly as
# lib/draft.sh does.
#
# Happy-path output goes to stdout via Write-Output. Errors are written via
# Write-Error; value cmdlets return $null and find/save/load/clear set
# $global:LASTEXITCODE. Source via dot-sourcing:
#   . path\to\lib\draft.ps1
#   Sti-DraftPath .stride 2026-05-12T103000 foo

# Strict mode is set inside each function, not at file scope: this file is
# dot-sourced into the caller's session, and a file-scope Set-StrictMode
# would leak into it (reading an unset variable in a later skill step would
# then throw). Each function still runs under -Version Latest.

function Sti-DraftPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir,
        [Parameter(Mandatory = $true, Position = 1)][AllowEmptyString()][string]$Timestamp,
        [Parameter(Mandatory = $true, Position = 2)][AllowEmptyString()][string]$Slug
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrEmpty($Dir) -or [string]::IsNullOrEmpty($Timestamp) -or [string]::IsNullOrEmpty($Slug)) {
        Write-Error 'Sti-DraftPath: usage: Sti-DraftPath <dir> <ts> <slug>'
        return $null
    }
    $dirTrimmed = $Dir.TrimEnd([char]'/', [char]'\')
    # Forward-slash join to match the bash output exactly.
    Write-Output "$dirTrimmed/$Timestamp-$Slug-draft.md"
}

function Sti-DraftFind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir,
        [Parameter(Mandatory = $true, Position = 1)][AllowEmptyString()][string]$Slug
    )
    Set-StrictMode -Version Latest
    # Latest NON-EMPTY draft for <slug> under <dir>, any timestamp. Writes the
    # path to stdout and sets LASTEXITCODE 0; on miss / absent dir sets
    # LASTEXITCODE 1 and writes nothing. Empty draft files are ignored so a
    # zero-length scratch never triggers a resume offer.
    if ([string]::IsNullOrEmpty($Dir) -or [string]::IsNullOrEmpty($Slug)) {
        Write-Error 'Sti-DraftFind: usage: Sti-DraftFind <dir> <slug>'
        $global:LASTEXITCODE = 1
        return
    }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        $global:LASTEXITCODE = 1
        return
    }
    # Anchored on the full YYYY-MM-DDTHHMMSS prefix (as lib/draft.sh's glob
    # is), so slug `auth` matches neither `oauth` nor `user-auth`.
    $namePattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}-' + [regex]::Escape($Slug) + '-draft\.md$'
    $candidates = @(
        Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -cmatch $namePattern -and $_.Length -gt 0 } |
            Sort-Object Name
    )
    if ($candidates.Count -eq 0) {
        $global:LASTEXITCODE = 1
        return
    }
    $dirTrimmed = $Dir.TrimEnd([char]'/', [char]'\')
    Write-Output "$dirTrimmed/$($candidates[-1].Name)"
    $global:LASTEXITCODE = 0
}

function Sti-DraftSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $true)][AllowEmptyString()][string]$Content
    )
    begin {
        Set-StrictMode -Version Latest
        $parts = New-Object System.Collections.Generic.List[string]
        $haveContent = $false
    }
    process {
        # Runs once for an argument, once per item for pipeline input, and
        # not at all for an empty pipeline.
        if ($PSBoundParameters.ContainsKey('Content')) {
            $parts.Add($Content)
            $haveContent = $true
        }
    }
    end {
        # Persist the content to <path>, creating the parent dir (which then
        # ignores itself). Side effects: that one file, the dir, and the dir's
        # .gitignore.
        if ([string]::IsNullOrEmpty($Path) -or (-not $haveContent -and -not $MyInvocation.ExpectingInput)) {
            # No content argument and no pipeline at all: a usage error, as in
            # lib/draft.sh, never an empty write over an existing draft. (An
            # empty pipeline still counts as input and writes an empty draft.)
            Write-Error 'Sti-DraftSave: usage: Sti-DraftSave <path> [<content>]  (or pipe the content in)'
            $global:LASTEXITCODE = 1
            return
        }
        $text = ''
        if ($haveContent) { $text = $parts -join "`n" }
        $dir = Split-Path -Parent $Path
        if ($dir) {
            Sti-DraftDir $dir
            if ($LASTEXITCODE -ne 0) {
                # Same message as before Sti-DraftDir existed: any failure to
                # place the draft reads as a failed write.
                Write-Error "Sti-DraftSave: cannot write scratch draft: $Path"
                $global:LASTEXITCODE = 1
                return
            }
        }
        try {
            # No trailing newline added, mirroring bash `printf '%s'`. .NET
            # resolves a relative path against the process directory, not the
            # PowerShell location, so resolve it first.
            $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            [System.IO.File]::WriteAllText($fullPath, $text, (New-Object System.Text.UTF8Encoding($false)))
            $global:LASTEXITCODE = 0
        } catch {
            Write-Error "Sti-DraftSave: cannot write scratch draft: $Path"
            $global:LASTEXITCODE = 1
        }
    }
}

function Sti-DraftDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Dir
    )
    Set-StrictMode -Version Latest
    # Create the scratch dir <dir> if needed and make it ignore itself, by the
    # same rule as lib/draft.sh's sti_draft_dir: write <dir>/.gitignore
    # containing `*` when it is absent AND this call created <dir> or <dir> is
    # named `.stride`. Never overwrites an existing .gitignore.
    if ([string]::IsNullOrEmpty($Dir)) {
        Write-Error 'Sti-DraftDir: usage: Sti-DraftDir <dir>'
        $global:LASTEXITCODE = 1
        return
    }
    try {
        $created = -not (Test-Path -LiteralPath $Dir -PathType Container)
        New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop | Out-Null
        $ignoreFile = Join-Path $Dir '.gitignore'
        if (-not (Test-Path -LiteralPath $ignoreFile) -and ($created -or (Split-Path -Leaf $Dir.TrimEnd([char]'/', [char]'\')) -ceq '.stride')) {
            # Same bytes as lib/draft.sh writes: "*" and a newline, no BOM.
            # .NET resolves relative paths against the process directory, so
            # resolve against the PowerShell location first.
            $ignoreFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ignoreFile)
            [System.IO.File]::WriteAllText($ignoreFull, "*`n", (New-Object System.Text.UTF8Encoding($false)))
        }
    } catch {
        Write-Error "Sti-DraftDir: cannot create scratch directory: $Dir"
        $global:LASTEXITCODE = 1
        return
    }
    # Inside a git work tree, make sure a draft name in <dir> is ignored.
    $probe = '0000-00-00T000000-probe-draft.md'
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if ($git) {
        $inside = & git -C $Dir rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            & git -C $Dir check-ignore -q -- $probe 2>$null
            if ($LASTEXITCODE -ne 0) {
                $exclude = & git -C $Dir rev-parse --path-format=absolute --git-path info/exclude 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $exclude) {
                    $exclude = (& git -C $Dir rev-parse --absolute-git-dir 2>$null) + '/info/exclude'
                }
                $prefix = & git -C $Dir rev-parse --show-prefix 2>$null
                try {
                    $excludeDir = Split-Path -Parent $exclude
                    if ($excludeDir) { New-Item -ItemType Directory -Path $excludeDir -Force -ErrorAction Stop | Out-Null }
                    [System.IO.File]::AppendAllText($exclude, "/$prefix*-draft.md`n", (New-Object System.Text.UTF8Encoding($false)))
                } catch { }
                & git -C $Dir check-ignore -q -- $probe 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Sti-DraftDir: drafts in $Dir would not be ignored by git (a .gitignore rule there re-includes them); refusing so a draft cannot be committed"
                    $global:LASTEXITCODE = 1
                    return
                }
            }
        }
    }
    $global:LASTEXITCODE = 0
}

function Sti-DraftLoad {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    Set-StrictMode -Version Latest
    # Emit the draft content at <path> to stdout. Errors if the file is absent.
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftLoad: usage: Sti-DraftLoad <path>'
        $global:LASTEXITCODE = 1
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "Sti-DraftLoad: no scratch draft at: $Path"
        $global:LASTEXITCODE = 1
        return $null
    }
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $global:LASTEXITCODE = 0
    Write-Output $content
}

function Sti-DraftExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    Set-StrictMode -Version Latest
    # Predicate: $true if <path> is an existing NON-EMPTY draft, else $false.
    # A zero-length scratch is treated as "no resumable draft".
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftExists: usage: Sti-DraftExists <path>'
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    return ((Get-Item -LiteralPath $Path).Length -gt 0)
}

function Sti-DraftClear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Path
    )
    Set-StrictMode -Version Latest
    # Remove the scratch draft at <path>. Idempotent: no error if already gone.
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error 'Sti-DraftClear: usage: Sti-DraftClear <path>'
        $global:LASTEXITCODE = 1
        return
    }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}
