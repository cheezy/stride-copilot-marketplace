# PowerShell mirror of test-stridify-retry.sh — exercises the classifier
# logic the Step 7c retry loop uses to bucket subagent dispatch outcomes
# into success / transient / terminal categories.
#
# The bash test inlines a `classify` function; the PowerShell mirror
# re-defines it as a cmdlet and exercises the same outcome strings.

Set-StrictMode -Version Latest

$script:PASS = 0
$script:FAIL = 0
function Pass($m) { $script:PASS++; Write-Host "  PASS  $m" }
function Fail($m, $d = '') { $script:FAIL++; Write-Host "  FAIL  $m"; if ($d) { Write-Host "        $d" } }

Write-Host 'test-stridify-retry.ps1 — exercises Step 7c retry classifier semantics'
Write-Host ''

# Mirror of the bash classify() function the skill body inlines. Inputs
# are the subagent dispatch result string; outputs are one of:
#   success | transient | unavailable | terminal
function Classify-Result {
    param([string]$Result)
    if ([string]::IsNullOrEmpty($Result)) { return 'terminal' }
    # success: contains a single fenced ```json block with a parseable object.
    if ($Result -match '(?s)```json\s*\n(\{.*?\})\s*\n```') {
        try {
            $null = $matches[1] | ConvertFrom-Json -ErrorAction Stop
            return 'success'
        } catch {
            return 'terminal'
        }
    }
    # unavailable: no custom-agent support, or the host does not know the
    # agent. Never retried; the skill runs the agent file inline instead.
    if ($Result -match '(?i)unknown (sub)?agent|no such agent|agent\b.*\bnot found|custom agents?\b.*\b(not supported|unavailable)') {
        return 'unavailable'
    }
    # transient: a rate-limit or capacity error from any model provider
    # (HTTP 429, 503, 529; rate limit / overloaded / capacity wording), or a
    # network error.
    if ($Result -match '\b(429|503|529)\b' -or $Result -match '(?i)too many requests|service unavailable' -or
        $Result -match '(?i)rate[ _-]?limit' -or $Result -match '(?i)overloaded' -or $Result -match '(?i)capacity' -or
        $Result -match '(?i)connection refused' -or $Result -match '(?i)could not resolve' -or
        $Result -match '(?i)timeout' -or $Result -match '(?i)tls handshake') {
        return 'transient'
    }
    # terminal: everything else (contract violation, hard 4xx other than 429).
    return 'terminal'
}

# Stage 1: well-formed success.
$ok = @'
```json
{"source_spec": "x", "goals": [{"title": "G", "type": "goal", "tasks": []}]}
```
'@
if ((Classify-Result $ok) -ceq 'success') { Pass "well-formed JSON -> success" } else { Fail "well-formed JSON should be success" }

# Stage 2: HTTP 529 (transient).
if ((Classify-Result 'HTTP 529: Overloaded') -ceq 'transient') { Pass "HTTP 529 -> transient" } else { Fail "HTTP 529 should be transient" }

# Stage 3: overloaded string (transient).
if ((Classify-Result 'API is overloaded right now') -ceq 'transient') { Pass "overloaded string -> transient" } else { Fail "overloaded should be transient" }

# Stage 4: network errors (transient).
if ((Classify-Result 'Connection refused on port 443') -ceq 'transient') { Pass "Connection refused -> transient" } else { Fail }
if ((Classify-Result 'Could not resolve host api.example.com') -ceq 'transient') { Pass "DNS failure -> transient" } else { Fail }
if ((Classify-Result 'Request timeout after 30s') -ceq 'transient') { Pass "timeout -> transient" } else { Fail }
if ((Classify-Result 'TLS handshake error') -ceq 'transient') { Pass "TLS handshake -> transient" } else { Fail }

# Stage 4b: provider-neutral rate-limit and capacity errors (transient).
foreach ($msg in @('HTTP 429 Too Many Requests', '503 Service Unavailable', 'Error: rate limit exceeded, retry after 20s',
                   'rate_limit_error: request was throttled', 'The model is at capacity, please try again later')) {
    if ((Classify-Result $msg) -ceq 'transient') { Pass "'$msg' -> transient" } else { Fail "'$msg' should be transient" }
}

# Stage 5: an unknown agent or no custom-agent support (unavailable: run the
# agent file inline, never retried).
foreach ($msg in @('agent type does-not-exist not found', 'unknown subagent type: requirements-decomposer',
                   'Custom agents are not supported in this environment')) {
    if ((Classify-Result $msg) -ceq 'unavailable') { Pass "'$msg' -> unavailable" } else { Fail "'$msg' should be unavailable" }
}

# Stage 5b: a number that merely contains 429 is not a status code (terminal).
if ((Classify-Result 'contract violation: response of 14290 tokens had no fenced JSON block') -ceq 'terminal') { Pass "14290 -> terminal" } else { Fail "14290 should be terminal" }

# Stage 6: hard 4xx other than 429 (terminal).
if ((Classify-Result 'HTTP 400: Bad Request') -ceq 'terminal') { Pass "HTTP 400 -> terminal" } else { Fail }
if ((Classify-Result 'HTTP 401: Unauthorized') -ceq 'terminal') { Pass "HTTP 401 -> terminal" } else { Fail }

# Stage 7: contract violation (no fenced JSON) (terminal).
if ((Classify-Result 'Here is your decomposition... no JSON anywhere') -ceq 'terminal') { Pass "no fenced JSON -> terminal" } else { Fail }

# Stage 8: malformed JSON inside fence (terminal).
$bad = @'
```json
not valid json {{
```
'@
if ((Classify-Result $bad) -ceq 'terminal') { Pass "malformed JSON in fence -> terminal" } else { Fail "malformed JSON should be terminal" }

# Stage 9: empty result (terminal).
if ((Classify-Result '') -ceq 'terminal') { Pass "empty result -> terminal" } else { Fail }

# Stage 10: backoff schedule sanity — 3 attempts total, sleep 30s then 90s.
# The bash test checks the documented schedule strings against the body of
# the stridify command. For the .ps1 mirror we confirm the schedule
# values are present in the skill body file via grep.
$skillBody = Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '../skills/stride-ideation-stridify/SKILL.md') -ErrorAction SilentlyContinue
if ($skillBody -and $skillBody -match 'sleep 30' -and $skillBody -match 'sleep 90' -and $skillBody -match 'MAX_ATTEMPTS=3') {
    Pass "skill body documents 3-attempt retry with 30s/90s backoff"
} else {
    Fail "skill body retry-schedule sentinels missing or skill file not found"
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
