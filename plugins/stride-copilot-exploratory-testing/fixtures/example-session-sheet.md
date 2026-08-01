# Example session sheet

A worked **session sheet** for charter #1 from the
[example charter set](example-charters.md), run by the `explorer` agent against the
fictional *ExpenseFlow* demo target. It follows the section skeleton from the
`session` skill in its **agent-run** form: the session is bounded by a probe budget
rather than a clock, so the sheet reports counts the agent actually kept instead of
wall-clock percentages. (A human-run sheet uses `TESTER / DATE / DURATION` plus Task
Breakdown Metric percentages — see the `session` skill; a human with a clock can
report those honestly, an agent cannot.) All data is synthetic; `demo.example.com`
and `<tenant A>` / `<tenant B>` are placeholders standing in for anything real.

---

```
CHARTER
  Explore the CSV receipt import with malformed, oversized, and wrong-encoding
  files (and files from another tenant's export) to discover how the parser fails,
  whether it corrupts existing receipts, and whether any row can leak across tenants.

TESTER / DATE
  explorer agent (stride-copilot-exploratory-testing) / 2026-07-20

SESSION BUDGET
  Probe budget: 12 (band 8-20)        Tool-call ceiling: 60
  Probes attempted: 7 (on-charter 6, off-charter 1)
  Probes that produced a finding: 5
  Tool calls used: 34
  Stopped: charter_quiet (5 of the 12 probes unspent - the budget is a
    ceiling, not a quota)

AREAS COVERED
  - CSV import screen (demo.example.com, <tenant A> account)
  - Parser behavior on: valid file, truncated file, 250 MB file, UTF-16 file,
    file with embedded commas/quotes, and a CSV exported from <tenant B>'s account
  - Post-import receipt list and running expense total
  - Import error banner and per-row rejection report

HEURISTICS APPLIED
  Follow the Data, Violate Format, Goldilocks, Change the Model

NOTES
  - Baseline: a clean 40-row CSV imports cleanly; total updates correctly. Good oracle
    for "did I break something."
  - Truncated file (cut mid-row): parser imports the first 39 rows, silently drops the
    partial 40th, no warning. Idea: is a silently-dropped row a data-integrity risk?
    -> filed as QUESTION, needs product intent.
  - 250 MB file: the upload never completed - the request eventually failed with a
    generic "Something went wrong" and no row detail. This one probe plus its setup
    cost 9 of the session's 34 tool calls; capped further size probes.
  - UTF-16-encoded file with accented vendor names ("Café Subroute"): names imported as
    mojibake ("CafÃ©"). Oracle = consistency with claims (the UI claims UTF-8 support in
    the help text). -> BUG.
  - Embedded-comma vendor ("Smith, Jones & Co"): parsed correctly (quoted field
    honored). No issue.
  - CRITICAL probe: imported <tenant B>'s exported CSV while logged in as <tenant A>.
    Rows imported into <tenant A> WITHOUT any tenant check. Cross-tenant data accepted.
    -> BUG (highest severity). Stopped to investigate and write repro.
  - Off-charter (opportunity): noticed the import screen has no file-type restriction —
    a .exe renamed to .csv is accepted for upload. Parked as a candidate charter.

BUGS
  1. [High] UTF-16 / non-UTF-8 CSVs import vendor names as mojibake, silently.
     Repro: import fixtures/utf16-vendors.csv as <tenant A> -> receipt list shows
     "CafÃ©" instead of "Café". Why wrong: UI help text claims UTF-8 support; the
     imported data is now corrupt and will export corrupt.
  2. [Critical] CSV import does not scope rows to the current tenant.
     Repro: while logged in as <tenant A>, import a CSV exported from <tenant B>;
     all rows are accepted and attributed to <tenant A>. Why wrong: violates tenant
     isolation — a Never/Always invariant ("data never crosses tenants").

QUESTIONS / RISKS
  - Is silently dropping a truncated final row acceptable, or should the import fail
    loudly? (product intent unknown)
  - What is the intended max file size, and should the generic error name the row/limit?
  - Is there any server-side file-type validation, or only the (absent) client check?

OFF-CHARTER PARKING LOT
  - No file-type restriction on the import upload (a renamed .exe is accepted).
    -> candidate charter: "Explore the import upload with disallowed and disguised
    file types to discover missing server-side validation."
  - Rapid double-submit of the same import — did it double-count? Not tested here.
    -> candidate charter (relates to charter #5, export double-count).
```

---

## How to read this sheet

- **SESSION BUDGET** replaces the human sheet's duration and Task Breakdown Metrics.
  An agent has no clock and cannot honestly report "Test 60% / Bug 25% / Setup 15%",
  so it reports what it counted as it went: **7 probes attempted**, **5 of them
  produced a finding**, **6 on-charter to 1 off-charter**, **34 tool calls**. The
  shape survives — most of the session served the charter, one detour produced a new
  candidate charter, and the setup-heavy oversized probe is visible as 9 tool calls
  spent on a single probe — but nothing here is estimated.
- **Stopped: charter_quiet** with 5 probes unspent is the point of the budget: it is
  a ceiling, not a quota. A session that stops because the charter went quiet is
  complete; one that stops on `probe_budget_exhausted` was budget-bound and there is
  probably more to find.
- **BUGS** are oracle-confirmed problems, each with a repro and a *why-wrong* — never
  just "looks off."
- **QUESTIONS / RISKS** hold things that need a human decision (product intent), which
  are not yet bugs.
- **OFF-CHARTER PARKING LOT** captures valuable detours as future charters instead of
  letting them derail this session.
