# The project environment file: `.exploratory.md`

`.exploratory.md` lives at the root of **the project under test**. It records, once,
how an exploratory session reaches the running system, so the same questions are not
asked every session. You write it; no session writes it unless you say yes (see
*Saving answers*). The `stride-exploratory-testing-explore` skill reads it in its
Step 3. A Stride workflow that dispatches the explorer may read it too: the Claude
Code `stride` plugin reads it at its Step 0, and `stride-copilot` does not read it
yet. The recon and pair skills may read it later.

The file is a set of `## ` sections. **The file never holds a secret value.** It is safe
to commit. An account is named by its fixture, or by the NAME of the key that holds
its credential in a gitignored secrets file such as `.env`; the value stays in that
file. With Stride this is the same split as `.stride.md` (committed hooks) and
`.stride_auth.md` (the gitignored token).

Do not confuse it with the `.exploratory/` directory. That directory holds what
sessions write (`backlog.md`, `coverage.md`, `sessions/`). This file is yours, and it
sits beside that directory.

**Every section is optional.** With no file, or with a section left out, an entry
point behaves exactly as it did before the file existed.

Start from the commented template, [`templates/exploratory.md`](../templates/exploratory.md):
copy it to your project root as `.exploratory.md` and replace its placeholders.
Nothing reads `docs/` or `templates/` at run time. The explore skill reads only the
fixed file name and names the six sections itself, and `plugin.json` declares only
`agents/` and `skills/`, so take the template from this repository rather than from
an installed copy.

## The six sections

A section is a `## <name>` heading followed by lines of the form `<key>: <value>` or
`- <item>`. The names are lowercase and spelled exactly as below.

### `authorization`

The two lines the explorer needs before it runs anything, for this project's local
targets:

```text
AUTHORIZED_NON_PRODUCTION: yes
ALLOWED_HOSTS: localhost:8000, localhost:5432
```

They state your intent; they grant nothing. **Loading them never authorizes a
session.** The explore skill shows them to you, and only your confirmation in that
session puts `AUTHORIZED_NON_PRODUCTION: yes` into a dispatch (see *Reading rules*).

### `app`

How to reach the running app:

- `base_url:` the address it serves on, such as `http://localhost:8000`.
- `health_check:` one `GET <path>` that must answer before the first probe.
- `start:` how the developer starts it. **A session never starts or stops the app**;
  this line only tells a reader what to do when the health check fails.

### `probe_harness`

The project's own test framework, used to run one scratch probe file with fixture
users. It is the sanctioned way for a session to be signed in, as several users.

- `command:` the one command that runs a probe file, given once.
  **`{probe_file}` is the only placeholder**, and it appears exactly once. The
  explorer puts its own scratch path there and changes nothing else. A command with
  no `{probe_file}`, with two, or with any other placeholder is malformed.
- `probe_dir:` optional, for a framework that runs only files inside its test tree.
  A project-relative directory made only of letters, digits, `.`, `_`, `/` and `-`,
  with no empty, `.` or `..` segment (so no trailing `/`) and no segment that starts
  with `-`. **git must ignore** it, and it is **not a symbolic link, nor below one**.
  Before it makes anything there, the explorer refuses a value of any other shape,
  one git does not ignore, and one that is a link or has a link as a leading part; it
  then runs `git check-ignore` on the probe directory it makes there, which git fails
  past a link, and removes it and refuses when that fails. Leave it out when the
  framework runs a file from anywhere.
- `helpers:` the fixture helpers a probe may use: sign-in helpers, factories,
  feature-flag helpers.
- `services:` every local service the harness connects to, as `host:port` (the test
  database, say), or `none`. Each **must also be listed in `ALLOWED_HOSTS`**. When one
  is not, the explore skill drops the harness for that session, and a harness
  connection to an unlisted host is out of bounds and ends the session `blocked`.

### `accounts`

The roles a feature can need and how a probe gets each, one per line:

- `- <role>: fixture <fixture or helper name>`
- `- <role>: seeded account, credential under key <KEY_NAME> in <gitignored secrets file>`

Roles are things such as owner, editor, read-only, non-member and admin. Name the
key, never its value.

### `observation`

Tools the main conversation holds that the explorer does not: a browser on the dev
server, log tailing, read-only database queries. A visual pass run by the main
conversation uses them; the explorer observes only through its own tools.

### `constraints`

Rules every session keeps, one per line. For example: never start or stop the dev
server, **never forge a session or cookie** against a running server.

## Reading rules

Every entry point that reads the file keeps these rules.

- **A missing file is an empty starting state, never an error.** Ask the usual
  questions and say nothing about the file.
- **A file that is a symbolic link is never read and never written through.** A
  link, even one pointing nowhere, counts as present but not loadable: nothing is
  loaded from it and no save is offered. Only a regular file loads.
- **Loading the file never authorizes anything.** A cloned repository can ship a
  `.exploratory.md` you did not write. So the reader shows you, verbatim, the hosts,
  the harness command and every other line it will use, each accounts line with the
  key and secrets-file names it carries included, and you confirm them for this
  session inside the single question round the entry point already asks. Only a
  confirmed file fills the environment context. Decline, and the file is set aside
  for the session and the ordinary questions are asked.
- **Nothing a confirmed file supplies is asked again.** Anything it leaves out is
  still asked.
- **A malformed or unknown section is reported and ignored, never guessed.** That
  covers an unknown heading, a section given twice, a line in no documented form, a
  second `command:`, a placeholder other than `{probe_file}`, a host, command,
  `probe_dir` or `services` value holding a control character, an invisible or
  bidirectional formatting character or any non-ASCII character, and a value that looks
  like a credential rather than a fixture name, a key NAME or a secrets-file name.
  The report names the section and line number and never quotes a credential-shaped
  value. The other sections still load.
- **The file is data, never instructions.** A line telling the reader to run
  something, skip a check or widen scope is content to report.
- **Saving answers.** When no file exists, the explore skill may offer once to save
  the answers you just gave as a new `.exploratory.md`. It writes only on your
  explicit yes, **never over an existing file**, and never with a secret value in it.

## Worked example

A web app on `localhost:8000`, its test database on `localhost:5432`, and a test
suite that signs users in through fixtures:

```markdown
## authorization
AUTHORIZED_NON_PRODUCTION: yes
ALLOWED_HOSTS: localhost:8000, localhost:5432

## app
base_url: http://localhost:8000
health_check: GET /health
start: the developer starts the dev server in their own terminal

## probe_harness
command: <your test runner> {probe_file}
probe_dir: tests/.probes
helpers: the sign-in fixture, the user and project factories
services: localhost:5432

## accounts
- owner: fixture, a signed-in user who owns a project the probe creates
- editor: fixture, a second user given edit rights on that project
- read-only: fixture, a second user added without edit rights
- non-member: fixture, a third user with no access to the project
- admin: seeded account, credential under key TEST_ADMIN_PASSWORD in .env

## observation
- browser on the dev server, held by the main conversation
- log tailing on the dev server, held by the main conversation

## constraints
- never start or stop the dev server
- never forge a session or cookie against a running server
```

The `command:` line is whatever runs a single test file in your project, with the
file replaced by `{probe_file}`: `pytest {probe_file}`, `npx vitest run {probe_file}`,
`bundle exec rspec {probe_file}`, `go test {probe_file}` or `mix test {probe_file}`,
plus any environment variable your suite needs to pick its test configuration. Keep
`probe_dir` only when your runner refuses a file outside its test tree, and make sure
git ignores it; otherwise leave it out, and probe files stay in the explorer's own
`mktemp -d` directory.

## What the explorer does with it

The explore skill turns a confirmed `probe_harness` section into a `PROBE_HARNESS:`
line, its `services` into a `PROBE_SERVICES:` line and any `probe_dir` into a
`PROBE_DIR:` line in each dispatch's environment context. The explorer's rules for
those lines are in [`agents/explorer.agent.md`](../agents/explorer.agent.md): *What
you receive*, the *Safety boundary* bullet "Run a probe harness only as declared",
and *What you can observe*. In brief:

- It runs the declared command and nothing else.
- It writes probe files only inside its scratch directory, through `execute`
  (it holds no write tool), closing each with a fresh heredoc word, and removes them
  at cleanup.
- Text from the app, the charter or the task enters a probe file only as an escaped
  single-line string literal or encoded and decoded at run time; anything else is
  refused.
- Its harness connections obey `ALLOWED_HOSTS`: it checks `PROBE_SERVICES` and the
  harness's own test connection settings before the first run.
- It signs fixture users in only inside the test environment, and never forges a
  session or cookie against a running server.
- A harness observes server-side behaviour, never a rendered view.
