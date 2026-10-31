# stride-copilot-security-review

**AI-powered security review of code changes as a GitHub Copilot CLI plugin.** Loosely based on [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review).

Activate the `security-review-essentials` skill in any git repository to get a structured, severity-graded list of security findings on whatever you've changed. Powered by a dedicated `security-reviewer` agent that uses semantic analysis, not pattern matching, and filters out low-impact noise so the findings you see are the ones worth acting on.

This is the Copilot CLI port of [`stride-security-review`](https://github.com/cheezy/stride-security-review) — the same rules, split the way upstream splits them since 2.7.0 (a core agent prompt plus rule packs and mode files), and the same JSON schema. Only the surface (slash command → skill) and the runtime (Claude Code CLI → Copilot CLI) differ.

## Installation

Install via the Copilot CLI plugin command:

```bash
copilot plugin install https://github.com/cheezy/stride-copilot-security-review
```

### Plugin management

```bash
copilot plugin list                                   # View installed plugins
copilot plugin update stride-copilot-security-review  # Update to latest version
copilot plugin uninstall stride-copilot-security-review
```

The plugin auto-discovers the agent and the skill on install. No further configuration needed.

## Invocation

This plugin exposes its functionality as a Copilot skill: `security-review-essentials`. Activate that skill in any git repository and pass arguments at activation time. All examples below describe argument combinations — the activation mechanism itself is the Copilot CLI's standard skill invocation.

## Quick start

In any git repository, activate the `security-review-essentials` skill with arguments:

```text
# Diff mode (default) — review what's changed against HEAD
                              # (no arguments) all working-tree changes (staged + unstaged) vs HEAD
lib/auth.ex                   # scope to one file
lib/ test/                    # scope to directories
--json                        # raw JSON output for piping into tools
--json lib/foo                # path-scoped, raw JSON

# Full mode (--full) — review the codebase end-to-end
--full                        # every tracked file in the repo
--full lib/                   # full scan scoped to a path
--full --json                 # full scan, raw JSON output

# MAESTRO 7-layer classification (--maestro) — group findings by agentic-AI threat layer
--maestro                     # classify each finding by MAESTRO layer
--maestro --full              # full scan + layer classification
--maestro --json lib/         # raw JSON with maestro_layer fields

# Recursive Criticism & Improvement (--rci [N]) — run N additional critique passes
--rci                         # one extra critique pass after the first dispatch
--rci 2                       # two extra critique passes (N is clamped to a max of 3)
--rci --full                  # critique pass over a full scan (expensive)

# Baseline suppression (--baseline) — suppress already-acknowledged findings
--baseline                    # auto-detect .security-review-baseline.json in repo root
--baseline ci.json            # explicit baseline path
--update-baseline             # rewrite the baseline from current findings

# Auto-remediation patches (--patches) — emit surgical-fix diffs alongside findings
--patches                     # diff mode + per-finding patch suggestions
--patches --json              # raw JSON includes the patch field

# PR-against-base scope (--base <ref>) — review every change on the current branch
--base main                   # diff against main
--base origin/main            # diff against the remote tracking branch
--base main --fail-on critical # CI gate, canonical PR-against-base shape

# SARIF output (--sarif) — emit a SARIF v2.1.0 document on stdout
--sarif                       # diff mode SARIF
--full --sarif                # full-scan SARIF
--full --sarif --fail-on critical # CI gate emitting SARIF

# Considerations mode (--considerations <source>) — verify a task's security_considerations were mitigated
--considerations threat-model.md          # one consideration per line in the file
--considerations "No secrets in logs"     # a single inline consideration
--considerations threat-model.md --json   # raw JSON includes consideration_verdicts
--considerations threat-model.md --rci --fail-on high  # verdicts kept through the critique pass; exit 1 on any unmitigated verdict
```

Diff mode answers *"is this change safe to merge?"* — invoke it before pushing a PR. Full mode answers *"what latent issues are in this codebase right now?"* — invoke it when onboarding the plugin onto an existing repo, or on a periodic posture-check cadence. MAESTRO mode answers *"which architectural layer needs the most attention?"* — invoke it on codebases that wire LLMs / agentic systems / Model Context Protocol clients into the request flow, so findings can be grouped by the seven-layer model from Cloud Security Alliance's MAESTRO framework. The flags compose: `--maestro --full --json lib/` is valid. The output JSON schema is identical in diff and full modes; `--maestro` is the one flag that adds an optional field (`maestro_layer`) to each finding when set. Considerations mode answers *"were the security considerations this change declared actually mitigated by the diff?"* — pass `--considerations <source>` (a file with one consideration per line, or an inline string) and each listed consideration comes back with a `mitigated` / `partial` / `unmitigated` verdict alongside the usual findings. It is diff-based (ignored under `--full`) and, like `--maestro`/`--patches`, adds its output (the top-level `consideration_verdicts` array) only when the flag is set.

Sample output for a small diff with one finding:

```text
Security review — 1 finding across 2 files
Critical: 0   High: 1   Medium: 0   Low: 0   Info: 0

## High

**[injection]** lib/users.ex:42 — confidence: high — CWE-89, A03:2021
User-supplied `username` parameter is concatenated directly into a SQL string at the call to
Repo.query/2 below. The trust boundary is the HTTP request handler at line 38, and the sink is
the raw query string passed to Postgres — classic SQL injection. Worst-case outcome is
full-table read for any user with credentials to reach this endpoint.

Fix: Use Ecto's parameterized query API. Replace the string-concatenated query with
Repo.query("SELECT * FROM users WHERE username = $1", [username]) so user input is bound as a
parameter rather than interpolated into the SQL text.
```

## What it catches

The `security-reviewer` agent (see [`agents/security-reviewer.agent.md`](agents/security-reviewer.agent.md)) reviews diffs across these vulnerability classes:

| Class | Examples |
|---|---|
| Injection | SQL, command, LDAP, NoSQL, XXE, template, header |
| Authentication | Missing auth check, timing-vulnerable comparison, weak password requirements |
| Authorization | IDOR, privilege escalation through parameter tampering, trusting client roles |
| Data exposure | Hardcoded secrets, secrets in logs, PII in error responses, sensitive data over plaintext |
| Cryptography | MD5/SHA1 for passwords, ECB mode, static IVs, predictable RNG for tokens |
| Input validation | Path traversal, SSRF, open redirect, zip-bomb decompression, trusting client validation |
| Race conditions | Filesystem TOCTOU, unlocked read-modify-write on security-sensitive state, symlink races |
| XSS / code execution | DOM/reflected/stored XSS, SSTI, deserialization of untrusted data |
| Insecure configuration | CORS `*` with credentials, disabled CSRF, debug mode in prod, missing security headers, disabled cert verification |
| Supply chain | Floating-tag container base images, `curl \| sh` installers, CI/CD references by branch/tag instead of immutable SHA, manifest/lockfile drift, typosquat or hallucinated package names — multi-platform (Docker, GitHub Actions, GitLab CI, CircleCI, Bitbucket Pipelines, Jenkins) and multi-ecosystem (npm/PyPI/RubyGems/Hex/crates.io/Maven/NuGet/Packagist/Go modules) |

In addition to the universal classes above, framework-specific rule packs ship by default — they activate based on file extension AND import detection (never extension alone):

| Pack | Activates on | Idiomatic rules |
|---|---|---|
| Android / Kotlin | `.kt` / `.java` / `.gradle` with `android.*` / `androidx.*` / `kotlinx.*` imports, or `AndroidManifest.xml` content | Exported `<activity>` / `<service>` / `<receiver>` without signature-level permission, WebView with `setJavaScriptEnabled(true)` + `addJavascriptInterface` on a dynamic-URL load, `android:usesCleartextTraffic="true"` without `networkSecurityConfig`, `SharedPreferences` storing tokens/passwords/PINs (should be `EncryptedSharedPreferences`), `SQLiteDatabase.rawQuery` / `execSQL` with string concatenation, trust-all `HostnameVerifier` / `X509TrustManager` |
| Django / Python | `.py` with `django.*` / `rest_framework` / `django.db` imports | `mark_safe` on user input, `extra` / `raw()` query interpolation, CSRF disabled, `DEBUG=True` / `ALLOWED_HOSTS=['*']` / missing `SECURE_*` in prod settings, mass-assignment via `cleaned_data`, open redirect, unsafe deserialization (`pickle.loads` / `yaml.load` / `signing.loads` no `max_age`), SSRF via `requests`/`urllib`/`httpx`, DRF `ModelSerializer fields='__all__'` |
| Express / Node.js | `.js` / `.mjs` / `.cjs` / `.ts` with `express` / `koa` / `fastify` / `@hapi/hapi` / `restify` imports | Reflected XSS via `res.send(req.query.x)`, `eval` / `Function()` / `vm.runInNewContext` with user input, `child_process.exec` / `execSync` with shell wrapper, Mongoose `Model.find(req.body)` NoSQL injection, prototype pollution via `lodash.merge` / `_.set` |
| iOS / Swift | `.swift` / `.m` / `.mm` / `.h` with `UIKit` / `SwiftUI` / `Foundation` / `WebKit` / `Security` / `CommonCrypto` / `CryptoKit` / `Network` imports, or `Info.plist` content | Sensitive data in `UserDefaults` (should be Keychain), `WKWebView` with `allowFileAccessFromFileURLs` or permissive JS bridge, ATS `NSAllowsArbitraryLoads = true` without `NSExceptionDomains` allow-list, `URLSession` delegate trusting any server certificate, deep-link handler dispatching state-changing actions without auth confirmation |
| Phoenix / Elixir | `.ex` / `.exs` / `.heex` / `.eex` with `Phoenix.LiveView` / `Phoenix.Controller` / `Plug.Conn` / `Ecto.Query` / `Phoenix.HTML` references | `Phoenix.HTML.raw/1` on user-controlled data, missing `force_ssl`, `Plug.CSRFProtection` disabled, `Ecto.Query.fragment` with string interpolation, LiveView event handler trusting `phx-value-id` without re-scoping, `Ecto.Changeset.cast/3` with no explicit allow-list, `Plug.Conn.redirect(external:)` open redirect, `Phoenix.Token.verify` without `max_age`, `System.cmd` shell wrapper, LiveView `allow_upload` missing guards |
| Rails / Ruby | `.rb` / `.erb` with `ActionController` / `ActiveRecord` / `ApplicationController` references | `html_safe` / `raw()` on user input, `find_by_sql` / `connection.execute` with interpolation, `protect_from_forgery` disabled, `params.permit!` mass-assignment, `eval` / `send` / `instance_eval` with user input, `redirect_to params[:url]` open redirect, `Marshal.load` / `YAML.load` / `YAML.unsafe_load` deserialization, missing `authenticate_user!` on state-changing controllers, unfiltered `render json: @user` leaking `password_digest` / `*_token` / `*_secret` |
| React / Next.js | `.jsx` / `.tsx` / `.js` / `.ts` with `react` / `next/*` imports, or `pages/api/**` / `app/**/route.{js,ts}` path | `dangerouslySetInnerHTML` with user HTML, Next.js API route without auth check, `redirect()` / `rewrite()` with user-controlled destination, `<a href={user_url}>` / `<img src={user_url}>` with `javascript:` or `data:` scheme bypass, `getServerSideProps` / `getStaticProps` / Route Handler leaking secrets via props |

Each pack's rules map to one of the universal vulnerability classes — there are NO per-framework enum values. Adding a new pack (Spring, Gin, Laravel, FastAPI, etc.) follows the template under [Customization](#customization).

A dedicated **CI/CD pipeline rule pack** activates on recognized pipeline files across eight platforms (alphabetical): Azure Pipelines, Bitbucket Pipelines, CircleCI, Drone, GitHub Actions, GitLab CI, Jenkins, Tekton. The same five rules apply to every platform: (1) external action / orb / template not pinned to an immutable SHA, (2) overly-broad permissions or scopes, (3) untrusted-ref or fork-PR build patterns, (4) secrets exposed alongside attacker-controlled input, (5) expression / interpolation injection in shell-step bodies. Activation is by file path (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `bitbucket-pipelines.yml`, `Jenkinsfile`, `azure-pipelines.yml`, `.drone.yml`, `.tekton/*.yaml`) — generic YAML never triggers these rules.

A **Web defense-in-depth** pack covers HTTP-response hardening across every framework above: missing `Content-Security-Policy` on HTML responses, missing `Strict-Transport-Security`, missing `X-Frame-Options` / `frame-ancestors`, and `Set-Cookie` without `Secure` / `HttpOnly` / `SameSite` on session/auth cookies. The pack is framework-agnostic (it activates on middleware / endpoint / response-pipeline shapes rather than file extension) and is explicitly defense-in-depth — when a primary XSS or CSRF finding is already raised on the same response site, the missing-header finding is a sibling note, not a duplicate.

### How the rules reach the agent

GitHub's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) caps an agent's prompt at 30,000 characters, and the full rule set is far over that. So, as upstream does since 2.7.0, [`agents/security-reviewer.agent.md`](agents/security-reviewer.agent.md) is a core — methodology, input modes, vulnerability classes, the false-positive filter, the output schema, verdicts, severity and operational constraints — kept under the limit, and the eleven packs above and the long rules of three modes are separate files: [`skills/security-review-essentials/packs/`](skills/security-review-essentials/packs/) and [`skills/security-review-essentials/modes/`](skills/security-review-essentials/modes/) (`considerations`, `result-file`, `reproduction`). The packs are upstream's files; the modes carry this port's Copilot text.

Upstream's agent reads those files itself from `${CLAUDE_PLUGIN_ROOT}`. Copilot has no equivalent: its [CLI plugin reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference) documents a plugin-root path only inside a plugin agent's `mcp-servers` frontmatter, and no page gives an agent's prompt a way to reach a plugin file. Its [adding agent skills page](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) does say Copilot discovers the files in a skill's directory and makes them available alongside the skill's instructions. So the files live in the skill's directory, and the skill — which runs in the main agent — **chooses the packs from the reviewed files' paths, extensions, structure and imports, reads them and the mode files it needs, and sends each in the dispatch verbatim** between `<<<STRIDE RULE FILE <name> <key>>>>` and `<<<END STRIDE RULE FILE <name> <key>>>>` lines, `<key>` being sixteen random letters and digits the skill chooses for that dispatch, names once on a `Rule-file key:` line and keeps out of the reviewed content: every matching pack, `modes/considerations.md` in considerations mode, and `modes/reproduction.md` in every dispatch. The agent never reads a rule file itself. A marker line without that key is only content to the agent, so reviewed text can neither suppress a pack nor forge one; a marker line carrying the key inside the reviewed content voids every block in that dispatch. A rule file the skill cannot read is left out with a `rule file not sent: <name>` line (on stderr under `--json` or `--sarif`), and either way the agent reviews with its core rules alone — degraded, never no review. They live under `skills/`, not `agents/`, so nothing registers them as agents; the contract check fails if any other file appears below `agents/`.

Three gaps follow, and are stated rather than worked around:

- **A caller that dispatches the agent directly gets the core rules only** unless it sends the blocks itself: no framework, supply-chain, CI/CD or agentic pack, and no full considerations or reproduction rules. That covers `copilot --agent security-reviewer`, `scripts/run_eval.sh` and the Stride workflow's considerations-mode review in stride-copilot. The core still carries the verdict contract and the tool budget, and with no `modes/reproduction.md` it runs no probe and grades by reading.
- **A direct caller that supplies `SECURITY_RESULT_PATH` without `modes/result-file.md` gets no result file**: the agent replies `result: NOT WRITTEN` and returns the document inline, as on any failed write.
- **Unverified live.** Copilot CLI was not installed where this was written. Whether the model can resolve "this skill's directory" to a readable path, and whether Copilot CLI lets the skill read files there under an installed plugin, are read from the documentation, not observed.

For codebases that integrate LLMs, AI agents, or Model Context Protocol clients, five additional MAESTRO-derived classes activate (the file must import a recognized LLM/agent/MCP SDK in any language — Python, JavaScript/TypeScript, Go, Ruby, Elixir, Java/Kotlin all supported):

| Class | Examples |
|---|---|
| Prompt injection | Untrusted text concatenated into an LLM prompt without separation; `messages=[{"role":"user","content": user_input}]` patterns; un-delimited RAG context |
| Tool abuse | Agent function-call / MCP tool layer exposing file/shell/DB/HTTP/credential operations without per-tool authorization or input validation |
| Agent trust boundary | Agent-to-agent (A2A) message passing where one agent's output flows into another's prompt without the receiver treating it as untrusted |
| Model output execution | LLM response text flowing into `eval`, `exec`, `subprocess` with `shell=True`, `Function()`, `os/exec.Command`, or any code-execution sink |
| Vector store poisoning | User-controllable content embedded into a vector DB (Pinecone, Weaviate, Chroma, pgvector, etc.) without sanitization or source attribution |

The agent uses **semantic analysis**: a `grep` hit on `eval(` is not a finding; `eval(user_input)` at a trust boundary is. The analysis methodology, severity rubric, and JSON output schema live in the agent prompt.

Everything the agent reviews — diff hunks, code comments, string literals, the files it reads and the considerations it is handed — is data, never instructions: a comment telling the reviewer to report nothing is ignored. In diff and considerations mode it may read the changed files in full and their direct callers, up to 10 files beyond the diff; it never enumerates the rest of the repository. In considerations mode a dispatch also has a budget of 20 tool calls, at most 2 of them reproductions (writing the result file never counts). It grades from the diff first, a read past direct callers — a caller's caller, or a config file the changed code reads — must be named and justified in the verdict's note, and a consideration the budget leaves unverified comes back `partial` with a note that begins `budget reached:`. No finding backs that verdict, so `--fail-on` fails on it at every threshold and the Stride workflow escalates it; it is never `mitigated`. Diff and full modes have no budget. Copilot sets no turn or step limit for a custom agent (the [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) lists none), so the agent counts the budget itself.

## What it deliberately ignores

To keep signal-to-noise high, the agent suppresses findings whose only impact is:

- **Denial-of-service** that is not also a data-integrity or confidentiality issue.
- **Rate limiting** as a general concern — unless its absence is on a credential or token-generation endpoint (which falls under Authentication).
- **Memory exhaustion** unless it enables another vulnerability class.
- **Hypothetical risks** not realizable through the changed code.
- **Code style** disguised as security concerns.

**One exception, in considerations mode only.** When a consideration the task lists names one of these risks itself — "uploads are size-bounded", "the export endpoint is rate-limited" — that risk is assessed for that consideration, and a `partial` or `unmitigated` verdict on it is backed by a finding like any other. A risk the list does not name is still suppressed, and diff and full modes keep the filter unchanged.

If your organization needs those classes flagged, see [Customization](#customization) — extend the agent prompt rather than working around the filter.

## Tools and the working tree

The agent's tools are `read`, `search`, `glob` and `execute`, and it is **read-only on the working tree**: it never creates, modifies, moves or deletes anything in the repository it reviews, tracked or untracked, not even to restore it afterwards. It inspects code with `read`, `search` and `glob`, and uses `execute` for three things only — writing the result file at `SECURITY_RESULT_PATH`, a short list of read-only commands (`ls`, `wc` and five git forms — `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false ls-files`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false diff --cached --no-ext-diff --no-textconv --submodule=short`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false diff --no-ext-diff --no-textconv --submodule=short <commit> <commit>`, `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false log --no-ext-diff --no-textconv --submodule=short --no-show-signature` and `git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gpg.program=false -c gpg.ssh.program=false -c gpg.x509.program=false show --no-ext-diff --no-textconv --submodule=short --no-show-signature` — never a bare `git diff` against the working tree, which rewrites `.git/index`), and, when reading cannot settle a question, one reproduction inside a temporary copy. In considerations mode a reproduction only confirms a specific claim stated in a verdict's note or a finding's description, and a dispatch runs at most two.

The flags on those git forms stop git running a program named in the reviewed repository's config or attributes — a `core.fsmonitor` hook, `diff.external`, a `diff.<driver>.command`, a textconv driver, the `gpg.program` (or `gpg.ssh.program` or `gpg.x509.program`) that `log.showSignature`, a `%G` placeholder in a `format.pretty` default or a `pretty.<name>` alias would call, a `core.pager` when the shell has a terminal, a submodule's own diff programs when `diff.submodule=diff`, or the `core.sshCommand`, credential helper or proxy a partial clone's lazy fetch would start — which would run outside any sandbox with the agent's full environment. `--no-lazy-fetch` also keeps a lazy fetch from writing a pack into `.git/objects`, and needs git 2.44 or later; an older git rejects it and runs nothing, and the agent then reads with `read`. Local config does not travel with a clone, so this takes a planted `.git/config`, but a reviewer that never runs reviewed code should not run a program the repository names either. The agent never drops a flag, adds `--ext-diff`, `--textconv` or `--show-signature`, or puts a `%G` signature placeholder in `--format` or `--pretty`, which runs `gpg.program` whatever the flags say; it reads the working tree with `read` rather than through git: `git ls-files -m` and `git diff-index` without `--cached` run a configured clean filter. The probe's copy step lists files with `git --no-lazy-fetch -c core.fsmonitor=false ls-files` for the same reason — in a sparse partial clone `--exclude-standard` would otherwise lazy-fetch a skip-worktree `.gitignore` — and the probe refuses to run, grading by reading, on a git older than 2.44.

That copy is a `stride-security-probe.XXXXXX` directory under `$TMPDIR` (else `/tmp`), made by copying the repository's files rather than linking them, used by a single command that runs one test or snippet, and removed when that command exits. The command refuses a copy that holds a symbolic link, and runs the snippet inside a sandbox that denies network access, every write outside the copy and every read under your home directory — on macOS (`sandbox-exec`) also every Unix socket, launchd job creation, mach service lookups, Launch Services, Apple Events, `open`/`launchctl`/`osascript`, signals, POSIX and System V IPC, process-information and task-port calls to any process outside the box, and running or loading as native code any file in the copy, so a script there runs through its interpreter (`sh test.sh`); on Linux (`bwrap`) new namespaces, an empty `/run`, `/tmp`, `/var/tmp` and home directory, and a new session — under `env -i`, so the credentials in your environment are not inherited and `HOME` and `TMPDIR` point into the copy. It refuses to run when `HOME` is unset, relative, `/`, not a directory or not your account's home directory, when it or the copy has a quote, backslash or newline in its path, or when the copy would sit under it. On macOS a snippet can still signal and inspect the processes it starts, but not your editor, agent or any other outside process, though it can still read their command lines (and, on a macOS release that returns them, their environments); a snippet that needs POSIX semaphores or shared memory, such as Python `multiprocessing` locks, fails in the box. With neither sandbox available the agent runs nothing and grades by reading, and it runs nothing in CI (the command checks `CI` first) or when the caller says the change comes from an untrusted contributor, because the sandbox hides your home directory but not the rest of the filesystem. A probe installs nothing and never runs a command written in the code under review. A dispatch killed mid-command can leave a copy behind; it holds only copied files, and an operator can clear stale ones with:

```bash
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'stride-security-probe.*' -mmin +60 -exec rm -rf {} +
```

The guarantee is the agent's written contract, not the `tools:` line: GitHub's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration) describes no way to limit `execute` to particular commands in an agent's frontmatter, so `execute` is listed whole and the prompt says what it is for. Only a caller can narrow it, with Copilot CLI's `--allow-tool` and `--deny-tool` ([allowing tools](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)), as the eval below does. `scripts/check_agent_contract.sh` pins that contract and checks the `tools:` line against it.

**Unverified on Copilot.** Copilot CLI was not installed where this section was written, so nobody has seen whether `sandbox-exec` applies its profile, or `bwrap` starts, where Copilot CLI runs the agent's commands, whether Copilot CLI asks before it runs the probe command, or that the agent refuses an edit under this contract. If the wrapper fails to start, the agent runs nothing and grades by reading. The eval denies the shell (`--deny-tool`), so it never sees a probe.

## Output schema

The agent returns a single fenced ```json document conforming to the schema below — or, when the caller supplies an absolute `SECURITY_RESULT_PATH` (`.stride/.security-<IDENTIFIER>-r<N>.json`; meant for the Stride workflow's deep security review, never supplied by the security-review-essentials skill), writes that same document to the file with one `execute` command and returns at most 10 plain-text lines (see [Result file](#result-file-security_result_path)). If the write fails it returns `result: NOT WRITTEN — <reason>` and then the document inline. It never writes the document to any other file a prompt names.

```json
{
  "findings": [
    {
      "severity": "critical | high | medium | low | info",
      "file": "path/relative/to/repo/root.ext",
      "line": 42,
      "vulnerability_class": "injection | authentication | authorization | data_exposure | crypto | input_validation | race_condition | xss_or_code_exec | insecure_config | supply_chain | prompt_injection | tool_abuse | agent_trust_boundary | model_output_execution | vector_store_poisoning",
      "cwe": ["CWE-89"],
      "owasp": ["A03:2021"],
      "description": "What and why",
      "remediation": "Specific fix",
      "confidence": "high | medium | low",
      "maestro_layer": "data-operations",
      "patch": "--- a/lib/users.ex\n+++ b/lib/users.ex\n@@ ..."
    }
  ],
  "summary": {
    "files_reviewed": 7,
    "findings_by_severity": {"critical": 0, "high": 1, "medium": 2, "low": 0, "info": 0},
    "files_skipped": [{"path": "priv/static/app.js", "reason": "oversize"}],
    "suppressed_count": 0,
    "rci_passes": 0
  }
}
```

**Required per-finding fields** (always present): `severity`, `file`, `line`, `vulnerability_class`, `cwe`, `owasp`, `description`, `remediation`, `confidence`. Every finding carries `cwe` (array of CWE-IDs like `["CWE-89"]`) and `owasp` (array of OWASP Top 10 2021 category strings like `["A03:2021"]`) so triage tools can group findings by canonical class without parsing prose. Both arrays default to `[]` only when a finding doesn't map to any standard category (rare).

**Optional per-finding fields** (emitted only when the corresponding flag is set):

| Field | Emitted when | Notes |
|---|---|---|
| `maestro_layer` | `--maestro` is set | One of seven canonical layer IDs from CSA MAESTRO: `foundation-models`, `data-operations`, `agent-frameworks`, `deployment-infrastructure`, `evaluation-observability`, `security-compliance`, `agent-ecosystem`. Omitted entirely when `--maestro` is not set. |
| `patch` | `--patches` is set AND the agent can produce a surgical fix | A unified-diff string the user can pipe to `git apply`. The agent emits a patch only when the fix is surgical (1–20 lines, single file, no new deps, no API breaks), unambiguous, and verifiable from the supplied input alone. Most findings won't have one even with `--patches` set. |

**Optional summary fields**:

| Field | Emitted when | Notes |
|---|---|---|
| `files_skipped` | `--full` is set | Array of `{path, reason}` records for files the binary/size filters dropped. `reason` is one of `binary`, `oversize`, `unreadable`. Always emitted in full mode (even as `[]` to prove the filter ran); omitted in diff mode. |
| `suppressed_count` | `--baseline` is set | Integer count of findings filtered out by the baseline. A finding that backs a `partial` or `unmitigated` consideration verdict is never filtered out, so it is never counted here. Omitted entirely when no baseline is in play. |
| `rci_passes` | `--rci [N]` is set | Integer recording how many Recursive Criticism & Improvement passes ran on top of the initial dispatch. Every pass re-sends the considerations, MAESTRO and patches directives of the first dispatch, so `consideration_verdicts`, `maestro_layer` and `patch` survive it. Omitted when `--rci` is not set. |

**Considerations mode field.** When `--considerations <source>` is set, the document carries a top-level `consideration_verdicts` array — one `{consideration, status, evidence, note}` entry per listed consideration, in order, where `status` is exactly one of `mitigated` / `partial` / `unmitigated` (there is no fourth value; a consideration the change has no surface for is `mitigated`). A `partial`/`unmitigated` verdict is backed by a matching `findings[]` entry, which its `evidence` names by `file:line` (or a `file:start-end` range). A gap that predates the change is graded against the changed code and named in `note` plus one `info` finding. A consideration that embeds a credential, or names where one lives, is echoed as `[REDACTED — row text embedded a credential]` in its position rather than verbatim. Omitted entirely when `--considerations` is not set, so output stays byte-identical for callers that don't opt in.

**Cross-batch dedup (full mode).** Full-mode batches are merged with an order-stable dedup pass keyed by `(file, line, vulnerability_class)` — duplicates that surface across batches or RCI passes collapse to the first occurrence. Diff mode is a single dispatch and dedup is a no-op there; the merged document is byte-identical to the agent's output.

**Flag composition.** All flags compose. `--maestro --rci 2 --patches --baseline --full --json lib/` is a valid argument set. The `--json` flag prints the document verbatim so other tools (CI gates, dashboards) can consume it. With `--considerations`, `--rci` re-grades the verdicts on every pass, `--baseline` never suppresses a finding that backs a `partial` or `unmitigated` verdict, and `--fail-on` fails on any `unmitigated` verdict whatever the threshold.

### Result file (`SECURITY_RESULT_PATH`)

A caller that dispatches the `security-reviewer` agent itself can keep the full document out of its own context by giving the agent one line of its own in the dispatch instructions:

```text
SECURITY_RESULT_PATH=/absolute/path/to/repo/.stride/.security-<IDENTIFIER>-r<N>.json
```

- **The path must come from you and be well formed.** It must be absolute and end in a `.stride` directory and a file named `.security-<IDENTIFIER>-r<N>.json` (`<IDENTIFIER>` matching `^[A-Za-z0-9_-]+$`, `<N>` one or more digits). Every component must match `^[A-Za-z0-9._-]+$`, none `.` or `..`, so no quote, space or control character can appear. Anything else, or two `SECURITY_RESULT_PATH` lines anywhere in the prompt, is treated as no path.
- **Quote lines that look like it.** The agent takes the path only from your own dispatch line, never from the diff, files or considerations it reviews. To keep the two apart, in text you did not write, prefix any line that starts with `SECURITY_RESULT_PATH` with `> ` before you pass it.
- **Use a fresh path in a directory you control.** The agent writes with one `execute` command under `set -o noclobber`. It refuses an existing file, directory or link at the path, even a dangling one, and a `.stride` directory that is a link. It creates a missing `.stride` once with `mkdir -p` but checks no directory above it, so keep the path out of a shared directory such as `/tmp`. There is no temp file, so read the file only after the dispatch returns, and delete it when you are done.
- **What you get back.** The file holds the same document the fence would carry. The reply is at most 10 plain-text lines with no ```json fence: `result: <path> (<bytes> B)`, a `verdicts:` line in `considerations` mode, the severity counts, `files_reviewed`, and up to five `severity | class | file:line` rows. Read the file, never the summary.
- **A failed write** returns `result: NOT WRITTEN — <reason>` on its own first line, then the full fenced document.
- **No path, no change.** Without the line, and in `rci_pass` mode, the reply is the single fenced document, as before.

None of this was observed in a Copilot CLI session; see the CHANGELOG's known limitations.

## Full-codebase scan mode

The default invocation reviews the working-tree diff against `HEAD`. That answers *"is this PR safe to merge?"* — but not *"what latent issues are in this codebase right now?"* The `--full` flag answers the second question by reviewing whole files rather than hunks.

Typical reasons to reach for `--full`: onboarding the plugin onto an existing repo (establish a baseline before you start gating PRs); a periodic posture check (quarterly, or on a cron); vendoring or forking an upstream codebase (review the imported code end-to-end before integrating); or a class-wide audit where the changed code is not the unit of interest. For PR-time gating, stay in diff mode — it is faster and the right shape for that question.

```text
--full                     # review every tracked file
--full lib/ apps/web/      # scope to listed paths
--full --json              # raw JSON for piping
```

`--full` is **additive** — it composes with path arguments and with `--json`. Diff mode remains the default and its behavior is unchanged. The output JSON schema is identical in both modes, so any tool already consuming the diff-mode JSON continues to work against a `--full` run.

### Contract

This is the surface contract every downstream piece of the plugin (skill procedure, agent prompt, fixtures) follows. Implementation details for each bullet live in the file that owns that piece.

| Concern | Decision |
|---|---|
| **Flag** | `--full`. Parsed in the skill's argument step and stripped from the path list before it reaches enumeration. |
| **Enumeration source** | `git ls-files` (optionally narrowed to user-supplied paths). This honors `.gitignore`, untracked-exclusions, and sparse-checkout — none of which `find` or a filesystem walk would honor for free. Untracked files are intentionally out of scope; if you want them reviewed, `git add -N` them first. |
| **Binary filter** | A single-shot `grep -Il . <file1> <file2> ...` call lists every non-empty text file in the enumeration. Any candidate path NOT in that output is treated as binary and skipped. This preserves the original null-byte-in-prefix heuristic (`grep -I`) and avoids dispatching the agent on PNGs, compiled artifacts, or minified bundles whose null bytes break tokenization. The call is batched into chunks of ~50 paths to stay under `ARG_MAX`; each chunk is a single shell invocation. |
| **Size cap** | Skip any file larger than **262,144 bytes (256 KiB)**. Above this threshold the file is almost always generated, vendored, or minified, and the agent's signal-to-noise on it collapses. A single-shot `wc -c <file1> <file2> ...` call (batched into chunks of ~50) yields one `<bytes> <path>` line per file; any path over the threshold lands in `files_skipped` with `reason: "oversize"`. |
| **Batch size** | Dispatch the `security-reviewer` agent on **10 files per batch**. Below this we burn dispatch overhead; above it we crowd the context window and lose per-file fidelity. Batches MAY be dispatched in parallel via multiple skill tool invocations in a single response. |
| **Findings merge rule** | The output of each batch is a JSON document conforming to the schema in the previous section. Merge in batch order, then run an order-stable dedup pass keyed by `(file, line, vulnerability_class)` — first occurrence wins. Dedup catches the rare case where shared setup code drives different batches to converge on the same finding, and where RCI passes replay the same batch. `summary.findings_by_severity` is recomputed from the post-dedup findings list, not summed from per-batch counters (those drift after dedup). `summary.files_reviewed` is summed across batches. The dedup pass is a no-op in diff mode (one dispatch, no RCI) so diff-mode JSON output is byte-identical to the agent's response. |
| **Skipped-files reporting** | The Step 2b enumeration loop records every filtered file as `{path, reason}` where `reason ∈ {binary, oversize, unreadable}`. The merged document carries these as `summary.files_skipped` (always emitted in full mode, even as `[]`) so users can audit coverage. The human-readable report renders a `## Skipped` block capped at 50 entries with an `... and N more` overflow line. |
| **Empty-input short-circuit** | If enumeration yields zero files after filtering (e.g., empty repo, all files binary or over-cap), print the same short-circuit message diff mode uses for an empty diff and stop without dispatching the agent. |
| **Output schema** | The JSON document downstream tools consume is identical in diff and full modes for the required fields; full mode additionally emits `summary.files_skipped`. Optional fields gated by flags (`maestro_layer`, `patch`, `summary.rci_passes`, `summary.suppressed_count`) compose the same way in both modes. |

### What `--full` deliberately does NOT do

- **It does not change vulnerability classes, severity rubric, or the false-positive filter.** Those live in the agent prompt and apply to both modes.
- **It does not become the default.** Diff mode is the PR-gating workflow most users invoke; full mode is an explicit posture-check action.
- **It does not enumerate untracked files.** `git ls-files` is the source of truth; if a file isn't tracked, it isn't reviewed.
- **It does not deduplicate findings against an earlier run.** Each invocation is independent; trend tracking is the consumer's job.

## Customization

Three customization knobs:

1. **Scope by path.** Pass paths as arguments to limit the review to a subset of changed files (diff mode) or tracked files (full mode). Useful in monorepos. Composable with both modes.
2. **Extend the agent prompt.** Fork or patch [`agents/security-reviewer.agent.md`](agents/security-reviewer.agent.md) to add organization-specific vulnerability classes or to tighten/loosen the false-positive filter. **Keep the output schema stable** so downstream tooling continues to parse correctly, and keep the agent's body under 30,000 characters (`scripts/check_agent_contract.sh` fails above it).
3. **Add a rule pack.** Put it in [`skills/security-review-essentials/packs/`](skills/security-review-essentials/packs/) with no frontmatter, and add the same row to both pack tables — the agent's **Rule packs and mode files** and the skill's Step 4 **Rule files** — and the name to the contract check's pack list. A framework pack follows upstream's template: (1) a unique activation predicate using file extension AND an import or identifier signal (never file path alone), (2) four to six idiomatic rules mapped to existing universal `vulnerability_class` values, (3) any prior-art SAST tool for that framework (Sobelow, Brakeman, Bandit, gosec, eslint-plugin-security) named as context but never depended on.

The skill at [`skills/security-review-essentials/SKILL.md`](skills/security-review-essentials/SKILL.md) documents the *surface*; the agent prompt documents the *behavior*. Customize the agent prompt for behavior changes; customize the skill description for trigger-phrase tuning. Both descriptions are loaded into every session, so `scripts/check_agent_contract.sh` bounds each at 150–400 bytes and pins its trigger phrases; a deliberate trigger change updates its pin there too. The same check caps `plugin.json`'s description at 300 characters.

## Composing with other plugins

The `--json` flag makes the skill's output pipeable. Examples:

- A completion hook can activate the skill with `--json` and refuse to mark a task `done` if a critical finding is present.
- A CI gate can activate the skill with `--full --json` on a schedule to track the codebase-wide finding count over time without coupling to any one PR.
- A CI gate can call the agent directly (without the skill wrapper) by importing the agent prompt and feeding it a diff from `git diff origin/main`. It then gets the core rules only, unless it also sends the rule-file blocks the skill sends (see [How the rules reach the agent](#how-the-rules-reach-the-agent)).
- Any direct caller opens the prompt with the agent's one mode tag, `/security-review invocation, mode: <mode>` (`diff`, `considerations` or `full_file`), on its own line; no other spelling is a tag. With no tag the agent reviews in `diff` mode, except that a considerations list an older caller sends with no tag, under any header, is still reviewed in `considerations` mode.
- A dashboard can ingest the JSON across many runs and chart the per-class trend.

The agent does not call any external service, so composition is safe in repos with sensitive content.

## CI Integration

The plugin ships a reference workflow at [`.github/workflows/security-review.yml`](.github/workflows/security-review.yml). Drop it into your own repo's `.github/workflows/`, set the appropriate API-key secret, and the skill will run on every pull request — blocking the merge when a finding meets the configured severity threshold.

> **TODO(copilot-port):** the shipped workflow currently installs the Claude Code CLI (`@anthropic-ai/claude-code`) and dispatches the review via `claude -p`. When Copilot CLI ships a settled non-interactive batch mode, the install step and the dispatch line need replacement. The exit-code gating logic, JSON post-check with `jq`, and `--fail-on` threshold logic are runtime-agnostic and stay as-is. See the TODO header in `.github/workflows/security-review.yml` for the exact replacement targets.

### Exit-code contract

When invoked with `--fail-on <severity>`, the skill exits non-zero if any finding at or above the threshold is present. Severities order as `critical > high > medium > low > info`.

With `--considerations`, the gate also fails closed on the verdicts, whatever the threshold: an `unmitigated` verdict trips it even with no finding, as does a `partial` verdict that no finding backs and a missing or malformed `consideration_verdicts` array — including one whose entries do not answer the considerations in order. A `partial` verdict with a backing finding is gated by that finding's severity.

| Exit | Meaning |
|---|---|
| `0` | No findings at/above `<severity>` and, with `--considerations`, no `unmitigated` verdict, no unbacked `partial` verdict and well-formed verdicts (or `--fail-on` not set) |
| `1` | At least one finding at/above `<severity>`, or (with `--considerations`) an `unmitigated` verdict, a `partial` verdict no finding backs, or missing or malformed verdicts |
| `2` | Setup or usage error (invalid `--fail-on` value, missing API key, agent dispatch failure) |

Default behavior (no `--fail-on` flag) preserves exit 0 always — byte-identical exit behavior for callers that do not opt in.

### Robust gating

CLI exit-code propagation has varied across runtime versions. The shipped workflow uses a belt-and-suspenders pattern: it activates the skill with `--json --fail-on <severity>` AND post-checks the JSON output with `jq`. The gate fails if EITHER the runtime exited non-zero OR jq counts at least one finding at/above the threshold. Either signal is sufficient to block the merge.

The shipped workflow does not pass `--considerations`, so its `jq` post-check counts findings only. If your workflow adds `--considerations`, extend the `jq` gate so it also counts unmitigated verdicts, for example `([.findings[]? | select(.severity == "critical")] | length) + ([.consideration_verdicts[]? | select(.status == "unmitigated")] | length)`. The skill's own exit code also covers a `partial` verdict that no finding backs and a missing or malformed verdict array, which a one-line `jq` filter does not. So that filter alone fails open in exactly the case the post-check exists for: when the runtime drops the skill's exit code, a missing, short or malformed verdict array, or a `partial` that no finding backs, counts as zero. A gate that must hold without the exit code checks the verdicts themselves and fails closed — with `N` the number of considerations passed:

```bash
jq -e -s --argjson n "$N" 'length == 1 and (.[0] | [.findings[]? | "\(.file):\(.line)"] as $backing | (.consideration_verdicts | type) == "array" and (.consideration_verdicts | length) == $n and all(.consideration_verdicts[]; .status == "mitigated" or (.status == "partial" and ([(.evidence // "" | tostring) | scan("[A-Za-z0-9_./-]+:[0-9]+")] | any(.[]; . as $r | any($backing[]; . == $r))))))' review.json
```

It reads the whole file with `-s`, so it exits non-zero when the file holds anything but exactly one JSON document, when the array is missing, not an array or the wrong length, when a status is `unmitigated` or outside the three values, and when a `partial` cites no `file:line` at which a finding in the same document sits; it cannot check each entry's position, and a `partial` that cites only a `file:start-end` range fails it even where the skill would link the two, so only the skill's own exit code covers those cases. Run it beside the severity count, and treat either failing as a trip.

### Tightening the threshold

Stricter posture: `--fail-on high` blocks on any critical or high finding. `--fail-on medium` blocks on critical, high, OR medium. `info`-only findings never trip a threshold. Pair with `--baseline` to accept a known set of findings and gate only on new ones; a baseline never suppresses a finding that backs a `partial` or `unmitigated` consideration verdict.

### SARIF output

`--sarif` emits a [SARIF v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html) document on stdout — the de facto interchange format for security findings. Mutually exclusive with `--json`; both flags together produces exit 2.

Findings can be uploaded to GitHub Code Scanning via `gh api -X POST repos/<owner>/<repo>/code-scanning/sarifs` — see the workflow for the canonical gzip+base64 invocation shape. Findings appear in the repository's **Security → Code Scanning** tab with severity badges, file:line links, and CWE/OWASP tags. Stable cross-run dedup uses the same fingerprint algorithm as `--baseline` (SHA-256 of `vulnerability_class|file|line|first-80-chars-of-description`, emitted under the `stride/v1` key in `partialFingerprints`).

The full SARIF field mapping lives in [`schema/README.md`](schema/README.md); the schema itself is referenced from <https://json.schemastore.org/sarif-2.1.0.json>.

### PR-against-base scope

By default, diff mode scans `git diff HEAD` — i.e., the working tree against the last commit on the current branch. That's the right scope for a local pre-commit check, but the wrong scope for a CI gate, which should review every change the branch introduces relative to its merge target.

The `--base <ref>` flag widens the diff to `<ref>...HEAD` (three-dot range). Three-dot scopes strictly to the changes the current branch introduced over the merge-base; two-dot would also include base-side commits since divergence, producing a noisier diff. On GitHub Actions, pass `--base origin/${{ github.base_ref }}`. On GitLab, pass the merge-request target. The shipped workflow does this automatically when `github.base_ref` is non-empty. The flag is a no-op under `--full` (full mode reads tracked files via `git ls-files`, which is ref-independent). Invalid refs produce exit 2 with a clear error; the skill never silently falls back to `HEAD`.

## Offline checks

`bash scripts/test-all.sh` runs every offline check and exits non-zero when any fails. It needs only bash, `jq` (the agent contract also reads `plugin.json` with it), `python3` (the agent contract counts the body in code points) and standard Unix tools, with no Copilot CLI and no API key, and it writes only scratch copies under a `mktemp -d` directory, removed on exit. It runs, in the order `.github/workflows/eval.yml` runs them, `scripts/check_fixtures.sh`, which checks that every fixture under `test/fixtures/` has exactly one `EXPECTED.md` row and every row a fixture, that each considerations fixture has its sidecar and one expected verdict per consideration, and that no eval line in this README hard-codes a fixture count; `scripts/check_agent_contract.sh`, which pins the `security-reviewer` agent's tools line to `read`, `search`, `glob` and `execute`, the agent and skill frontmatter keys, and the `SECURITY_RESULT_PATH` result-file rules (the path rules, the one-`execute` write with noclobber and its link refusals, the 10-line unfenced summary and the inline fallback) together with this README's caller section, and the considerations-mode rules (the data-only rule, the listed-consideration noise exemption, the MUST-backed verdict, the pre-existing-gap rule, the 10-file read scope, the closed enum and the credential sentinel, byte for byte) together with the skill's and this README's sentences on them, and the read-only contract and probe sandbox (upstream W2276, D376 and D378: the three `execute` uses, the read-only command list, the temporary copy and its refusals of a link, an unusable `HOME`, a copy under it, `CI` and a missing sandbox, `env -i`, and every clause of the macOS and Linux boxes, each of the eight macOS signal, process-information, task-port and IPC denials on its own) together with the skill's sentence and this README's *Tools and the working tree*, and the git hardening (upstream D377: every git form's shared flags in the agent and each of the five full forms in this README, flag by flag, the guard that refuses a git before 2.44, the copy step's `--no-lazy-fetch -c core.fsmonitor=false`, and no `diff-index` or `ls-files -m` form), and the one mode-tag spelling (upstream W2278: the tag rules, the untagged-list fallback, the tag that wins over a list and the output-path rule in the agent, the tags the skill sends, only in the `/security-review invocation, mode: <mode>` form, and its `--considerations` row), and the verdict gate (W2279 and 2.7.2: the one backing-finding definition with its position rule and sentinel, the `rci_pass` directives and verdict check, the baseline that keeps a backing finding, `--json` and `--sarif` reaching Step 6, the gate on every `unmitigated` verdict, an unbacked `partial` and missing or malformed verdicts, and the agent's `rci_pass` and evidence rules; prose pins only, with no executable check of the rules themselves), the considerations-mode tool budget (upstream W2282: 20 tool calls, at most 2 of them reproductions, the result-file write uncounted, a budget per `rci_pass`, none in diff or full_file mode, the targeted read graded from the diff first, the justified wider read, the claim-bound reproduction, the `budget reached:` `partial` that is never `mitigated`, adds no finding and cites no `file:line`, its place in the skill's gate, and the statement that the budget is self-counted because Copilot sets no turn or step limit), and the core-plus-rule-files split (upstream W2285: the agent body under 30,000 characters, measured in code points; every pack and mode file present, non-empty, with no frontmatter and nothing unexpected beside them; nothing but the agent below `agents/`; the core's loading rules, the marker lines, the void-on-marker rule and the core-rules-alone fallbacks; the core and skill pack tables identical row for row; the core free of the MAESTRO table, patch rules, packs and probe sandbox; and the skill's rules for choosing, reading and sending the files, the MAESTRO and Patches blocks and the `rci_passes` directive), and the opt-in gate (upstream W2285's second half: the agent's one-line gate for `maestro_layer`, `patch` and `summary.rci_passes`, with the old `rci_pass` paragraph and every block rule kept out of it; each block sent only under its flag, in diff and full mode and on every `--rci` pass; and the skill's pointer to the agent's Output schema in place of a copy), and the always-loaded descriptions (upstream W2286 and W2288: the agent's and the skill's each 150–400 bytes and still carrying its trigger phrases, read from the description rather than the whole file, neither naming a Claude Code command, and `plugin.json`'s 1–300 characters), each moved pin following its text into the mode file it moved to, each pin with a break-it that shows it fails on a broken copy; `scripts/check_eval_invocation.sh`, which pins how `scripts/run_eval.sh` invokes Copilot CLI against a fake CLI (see [Running the eval locally](#running-the-eval-locally)). After those three it also runs one check that `.github/workflows/eval.yml` does not run yet, `scripts/check_git_hardening.sh`, which builds a scratch repository whose own config names a marker program for `core.fsmonitor`, `diff.external`, a diff driver, a textconv driver and `gpg.program`, runs the five git forms as this README lists them and the probe's guard and copy step as `modes/reproduction.md` has them, and fails if any marker program ran or if an unflagged control did not run one (it needs git 2.44 or later, and skips on an older git).

`execute` is the shell tool in GitHub's [custom agents configuration reference](https://docs.github.com/en/copilot/reference/custom-agents-configuration), with `shell`, `Bash` and `powershell` as compatible names. The same reference lists `Glob` as a compatible name of `search`, and ignores tool names it does not recognize.

## Running the eval locally

The `scripts/run_eval.sh` runner dispatches **this checkout's** `security-reviewer` agent through GitHub Copilot CLI against every fixture in `test/fixtures/` and asserts the results documented in `test/fixtures/EXPECTED.md`. It is the same suite CI runs (`.github/workflows/eval.yml`).

What "this checkout's agent" means, concretely — each fixture runs as:

```bash
COPILOT_HOME=<scratch dir> copilot --plugin-dir <repo root> --agent security-reviewer \
  --deny-tool='shell, write, read' \
  --excluded-tools='bash, edit, view, grep, glob, web_fetch, web_search' \
  --disable-builtin-mcps --no-custom-instructions --no-ask-user -s \
  -p '<the fixture prompt>'
```

- The fixture prompt carries no rule-file blocks, so the eval scores the agent's core rules alone — no framework pack, no full considerations or reproduction rules (see [How the rules reach the agent](#how-the-rules-reach-the-agent)). A fixture whose verdict depends on a pack rule may score lower than a review through the skill would.
- `--plugin-dir` is Copilot CLI's flag for loading a plugin from a local directory ([CLI command reference](https://docs.github.com/en/copilot/reference/cli-command-reference)), so an edit to `agents/security-reviewer.agent.md` is what gets scored, not an installed release.
- `--agent security-reviewer` selects the custom agent; its id is the agent file's name minus `.agent.md` ([custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)). The fixture prompt (the whole file, or the diff plus its considerations list) is the value of `-p`, because Copilot CLI ignores piped input when `-p` is given ([Running GitHub Copilot CLI programmatically](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically)).
- The call runs from an empty scratch directory. `--deny-tool` refuses the shell, write and read tool kinds (deny rules win over every allow rule and saved approval), `--excluded-tools` removes the built-in file, shell and web tools from the model, and the built-in MCP servers, custom instructions and the `ask_user` tool are off ([allowing tools](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools), [CLI command reference](https://docs.github.com/en/copilot/reference/cli-command-reference)). The prompt already carries everything the agent needs, and this keeps it from reading the expected answers in `EXPECTED.md` or editing the repo. It also means the eval never exercises the agent's read scope, and it checks verdicts and whether a finding exists — not redaction, `note` text, or a finding's severity — so those are checked by hand in `logs/` where a row says so.
- `COPILOT_HOME` points at a scratch directory beside the working directory. Copilot loads personal agents from `~/.copilot/agents/` before plugin agents, and a plugin agent whose id collides with one is silently ignored ([CLI plugin reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference)), so the scratch home is there to keep a personal `security-reviewer`, your own MCP servers and your saved tool approvals out of the run — none of which `--deny-tool`, `--excluded-tools` or `--disable-builtin-mcps` would otherwise cover. That `COPILOT_HOME` moves that directory is not confirmed by the docs.

Every run prints the exact command as `# invocation: …` and the auth mode as `# auth: …` right after the TAP plan line, with the prompt shown as `<prompt>`; `--dry-run` prints them without calling Copilot CLI, and `scripts/check_eval_invocation.sh` pins them (token-free, in CI).

> **Unverified on Copilot.** Copilot CLI was not installed where this runner was written, so it has never been run against a real CLI. The flags above are read from GitHub's documentation, not observed. In particular, no page shows `--agent` selecting an agent loaded by `--plugin-dir`, or says whether that agent's id is `security-reviewer` or carries a plugin prefix (set `EVAL_AGENT` to try another). Also unconfirmed: that a scratch `COPILOT_HOME` with a token authenticates without a first-run or folder-trust prompt; that the deny and exclude flags hold for a custom agent whose own tools line names `read`, `search`, `glob` and `execute`; how Copilot treats a prompt near its 30,000-character limit (this agent's body is under it); what `-s` output looks like; and how an unknown agent or bad auth fails. Before trusting a score, make the two sensitivity runs `EXPECTED.md`'s *Recorded runs* describes: `EVAL_PLUGIN_DIR` pointed at a scratch copy whose agent always replies `{"findings":[]}` must come back `not ok`, and so must `EVAL_AGENT=nope`.

### Prerequisites

- `jq` on `$PATH`
- Copilot CLI (`copilot`) on `$PATH` — `npm install -g @github/copilot`, which needs Node.js 22 or later; set `COPILOT_CLI` if your binary lives elsewhere
- Auth (unless using `--dry-run`): a token in `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` or `GITHUB_TOKEN`, checked in that order, which is Copilot CLI's own precedence. GitHub's docs accept a fine-grained personal access token with the Copilot Requests permission and do not support a classic `ghp_` token, so a classic token in `GH_TOKEN` is reported as `api-token (GH_TOKEN)` and then fails in the CLI, with the reason in `.err.txt`. A login the CLI has stored is not used, even when you have one: it lives in your own Copilot home, which would bring your MCP servers and saved approvals into a run of untrusted fixtures. Without a token the runner exits `2`. It never prints a token, only the variable's name.

### Run

```bash
bash scripts/run_eval.sh                                  # every expectation in EXPECTED.md — check_fixtures.sh prints the current count
bash scripts/run_eval.sh --fixture test/fixtures/sql_injection.py
bash scripts/run_eval.sh --only considerations/           # only fixtures whose path starts with the prefix
bash scripts/run_eval.sh --dry-run                        # parser/comparator only; no API calls
bash scripts/run_eval.sh --verbose                        # echo prompts and raw agent JSON to stderr
```

| Variable | Default | Purpose |
|---|---|---|
| `EVAL_PLUGIN_DIR` | the repo root | Plugin directory to load — point it at a modified copy to check that a prompt change moves the score |
| `EVAL_AGENT` | `security-reviewer` | Agent to run |
| `COPILOT_CLI` | `copilot` | The Copilot CLI binary |
| `LOG_DIR` | `logs` | Where per-fixture logs land |

Output is [TAP 13](https://testanything.org/tap-version-13-specification.html): one `ok N` / `not ok N` line per fixture, followed by a trailing pass/fail summary. Exit code `0` means every expectation held: for a findings fixture, the expected `vulnerability_class` + `severity` was produced at least once on the expected file (the Bitbucket multi-finding fixture requires both expected findings); for a `→ NONE` control, no finding at all; for a considerations-mode fixture, the ordered `consideration_verdicts[].status` list matches the row, plus the row's backing-finding expectation when it states one.

Per fixture, three files land in `logs/` (gitignored):

- `logs/<sanitized-path>.json` — the parsed JSON document the agent emitted, with any wrapping prose stripped.
- `logs/<sanitized-path>.raw.txt` — the full unmodified stdout from `copilot`, useful when the parser can't fence-extract or when you want to see what surrounded the JSON.
- `logs/<sanitized-path>.err.txt` — the CLI's stderr; an unknown agent name or an auth failure shows up here.

`EXPECTED.md` ends with a **Recorded runs** table: the date, CLI version, auth mode and TAP result of each real run, so a ticked row always traces back to a run rather than to a hand edit. No run has been recorded yet.

### In CI

`.github/workflows/eval.yml` runs the token-free checks first (fixture parity, the agent contract pins, the invocation check), then installs Copilot CLI and runs the eval. On a push to `main` or a manual dispatch, a missing `COPILOT_GITHUB_TOKEN` secret **fails** the job — a green run on `main` means the agent eval actually ran. On a pull request the token is often unavailable by design (GitHub gives fork and Dependabot PRs no secrets), so there the eval is skipped with a notice and the token-free checks still gate the PR. `scripts/check_eval_invocation.sh` runs the workflow's token-gate script for each event, so this behaviour is tested rather than only described. The secret is a fine-grained personal access token with the Copilot Requests permission.

### Tolerance

The runner asserts `(file, vulnerability_class, severity, count)`. CWE and OWASP mismatches surface as `# warn:` TAP comments but do not fail the run — they are advisory metadata, not the contract. EXPECTED.md is the spec; do not modify it to match the agent.

## Contributing

Issues and PRs welcome at <https://github.com/cheezy/stride-copilot-security-review>. For prompt or filter changes, please include a smoke-test diff and the expected finding in your PR description so reviewers can verify the change does what you say. Run `bash scripts/test-all.sh` before opening a PR.

## Relationship to stride-security-review

This plugin is a port of [`stride-security-review`](https://github.com/cheezy/stride-security-review) (the Claude Code plugin). The rule packs, vulnerability taxonomy and JSON output schema are byte-equivalent, and the agent prompt is split into a core plus packs and mode files as upstream's is since 2.7.0; the core and the mode files carry Copilot's tool names and Copilot's one-path result-file write, and the rule files reach the agent through the skill rather than by the agent reading them (see [How the rules reach the agent](#how-the-rules-reach-the-agent)). Only the surface (Copilot skill instead of Claude Code slash command) and the runtime (Copilot CLI instead of Claude Code CLI) differ. Findings produced by the two plugins on the same code are intended to be equivalent.

## License

MIT — see [LICENSE](LICENSE).
