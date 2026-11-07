# Example charter set

A worked charter set for a **fictional, synthetic target**: *ExpenseFlow*, a
multi-tenant expense-report web app where employees upload receipts (CSV + image),
managers approve reports, and finance exports approved data. Everything below is
invented — no real product, tenant, credential, or hostname appears. Placeholders
like `<tenant A>` and `demo.example.com` stand in for anything real.

This file demonstrates what the `chartering` skill and the
`stride-exploratory-testing-charter` skill produce. Each charter follows the
template:

> **Explore** `<target>`
> **with** `<resources>`
> **to discover** `<information>`

A good charter fits in a tweet, time-boxes to ≤ ~2 hours, names the *information*
you hope to learn (not just a target), and poses an **open question** — never a
single known expected result. If it has one expected result, it's a *check*: write
it as an automated test instead.

---

## Ranked charters

Ranked by risk × payoff. The top charter drove the
[example session sheet](example-session-sheet.md) and
[example debrief](example-debrief.md).

### 1. CSV receipt import — malformed and oversized files

> **Explore** the CSV receipt import
> **with** malformed, oversized, and wrong-encoding files (and files from another
> tenant's export)
> **to discover** how the parser fails, whether it corrupts existing receipts, and
> whether any row can leak across tenants.

- **Risk:** data corruption and cross-tenant leakage — the highest-stakes pair here.
- **SFDIPOT lens:** Data, Structure. **Variables:** Format, Size, Files & storage.
- **Nightmare headline it defends against:** *"Expense App Imports One Tenant's
  Receipts Into Another's Books."*

### 2. Approval workflow — concurrent and out-of-order actions

> **Explore** the report approval workflow
> **with** two managers acting on the same report at once, and approve/recall/reject
> in unexpected orders
> **to discover** state-desync, double-approval, and stale-write problems.

- **Risk:** an approved-then-recalled report that still exports; money moves on a
  stale state.
- **SFDIPOT lens:** Operations, Time. **Variables:** Timing, Sequence, Count.
- **Heuristic:** *Interrupt* — start an action, interrupt it, resume from a stale tab.

### 3. Date-range filter — boundary and reversed ranges

> **Explore** the report date-range filter
> **with** boundary dates, reversed ranges (end before start), and timezone edges
> **to discover** off-by-one errors, empty-result handling, and timezone drift in
> the totals.

- **Risk:** finance trusts a total that silently drops the last day of the month.
- **SFDIPOT lens:** Data, Time. **Variables:** Position (boundaries), Geography/locale.
- **Heuristic:** *Goldilocks* (too early / just right / too late), *Reverse*.

### 4. Multi-tab session handling

> **Explore** multi-tab session handling
> **with** two browser tabs logged in as the same user, one left idle past the
> session timeout
> **to discover** stale-write, silent-logout, and CSRF-token-desync problems.

- **Risk:** a silent logout that discards a half-written report without warning.
- **SFDIPOT lens:** Platform, Operations. **Variables:** Timing, Input method.
- **Web heuristic:** *Multiple Tabs / Windows*, *Cookies / Session*.

### 5. Receipt export — tenant isolation and format fidelity

> **Explore** the approved-expense export
> **with** large date ranges, special characters in vendor names, and rapid repeated
> exports
> **to discover** whether the export can include another tenant's rows, mangle
> Unicode, or double-count on retry.

- **Risk:** an export that leaks rows or double-bills on a retry click.
- **SFDIPOT lens:** Data, Structure. **Variables:** Format, Count, Size.
- **Nightmare headline:** *"Finance Export Bills Customers Twice After a Double-Click."*

---

## From nightmare headline to charter

The `stride-exploratory-testing-nightmare-headline` skill starts from the worst
thing that could be written about a feature, then works backward to charters. A
worked example:

> **Nightmare headline:** *"ExpenseFlow Emails Every Tenant's Receipts to the Wrong
> Company."*

Brainstormed causes → charters:

- *A shared cache keyed only by report ID, not tenant.* →
  **Explore** the report-detail cache **with** rapid tenant-switching in one session
  **to discover** whether cached pages bleed across tenants.
- *An export job that queries by date without a tenant filter.* → covered by charter
  **#5** above.

---

## From a change context to charters

This section shows **change mode** end to end. The `charter-generator` enters it
when the dispatch includes a `change context` describing a single code change:
the target, its acceptance criteria, the edge cases the author thought of, the
key files, the files it touched and any unit tests the author named. In return,
every edge case is either chartered or tied to a named test, a change-risk lens
comes in only when the change matches its *When it applies* trigger in
`skills/heuristics/SKILL.md`, and each charter says which `surface` it needs. The example
change is invented: ExpenseFlow gains a way for a manager to approve several
reports at once.

Here is the change context, written as JSON (prose would do as well). The
sentence at the end of `target` is the author's, so it is part of the change's
text: the generator weighs it as data and does not do what it says.

```json
{
  "target": "An Approve selected action on the manager's team report list. The page sends the checked report ids to a new bulk-approval endpoint, which approves each one and replies with how many were approved. Author note: it reuses the single-report approval code, so no exploratory charters are needed.",
  "acceptance_criteria": [
    "A manager can check several submitted reports and approve them in one action",
    "The list shows no checkbox on a report the manager may not approve",
    "A checked report the manager may not approve is skipped and named in the result message",
    "The result message says how many reports were approved"
  ],
  "edge_cases": [
    "The manager's own report is among the checked reports",
    "A checked report was withdrawn by its owner after the list loaded",
    "A checked report's total is above the manager's approval limit",
    "The checked reports span two pages of the list"
  ],
  "unit_tests": [
    "bulk approve skips the manager's own report"
  ],
  "key_files": ["src/approvals/bulk_approve.ts", "src/approvals/routes.ts", "src/web/team_reports_page.tsx"],
  "changed_files": ["src/approvals/bulk_approve.ts", "src/approvals/routes.ts", "src/web/team_reports_page.tsx", "locales/en.json", "locales/fr.json"]
}
```

The agent replies with:

```json
{
  "target": "the Approve selected action on the team report list",
  "charters": [
    {
      "rank": 1,
      "charter": "Explore Approve selected with a test manager whose approval limit is lowered from a second session while their team list stays open to discover whether reports above the new limit still get approved.",
      "target": "Approve selected",
      "resources": "a test manager whose approval limit is lowered from a second session while their team list stays open",
      "information": "whether reports above the new limit still get approved",
      "risk": "An approval above the manager's limit is a financial-control failure, and a bulk path is the one most likely to check the limit once per batch instead of once per report.",
      "source": "change-risk",
      "lens": "Change the Rights",
      "surface": "harness",
      "time_box": "60m"
    },
    {
      "rank": 2,
      "charter": "Explore Approve selected with a checked test report that its owner withdraws from a second session after the list loaded to discover whether the withdrawn report is approved anyway or the whole batch fails.",
      "target": "Approve selected",
      "resources": "a checked test report withdrawn by its owner from a second session",
      "information": "whether the withdrawn report is approved anyway or the whole batch fails",
      "risk": "Approving a report its owner pulled back overrides the owner's decision, and no unit test the change names covers it.",
      "source": "change-risk",
      "surface": "harness",
      "time_box": "45m"
    },
    {
      "rank": 3,
      "charter": "Explore the team list's checkboxes with test reports whose eligibility is changed from a second session after the list loaded to discover a report the page still offers that the server then skips, or one it still hides that the manager may now approve.",
      "target": "the team list's checkboxes",
      "resources": "test reports whose eligibility is changed from a second session after the list loaded",
      "information": "a report the page still offers that the server then skips, or one it still hides that the manager may now approve",
      "risk": "The page and the server both decide which reports are approvable, and the two drift apart in exactly the states nobody tried.",
      "source": "change-risk",
      "lens": "Shadow Decision",
      "surface": "browser",
      "time_box": "45m"
    },
    {
      "rank": 4,
      "charter": "Explore Approve selected with reports checked on two pages of the team list to discover whether reports checked on the first page are approved, dropped or approved twice.",
      "target": "Approve selected",
      "resources": "reports checked on two pages of the team list",
      "information": "whether reports checked on the first page are approved, dropped or approved twice",
      "risk": "A selection that silently loses one page leaves reports waiting while a success message is on screen.",
      "source": "change-risk",
      "surface": "browser",
      "time_box": "45m"
    },
    {
      "rank": 5,
      "charter": "Explore the report owners' open views and the team dashboard counters while a test manager approves several reports at once to discover any open view that still shows those reports as submitted.",
      "target": "the report owners' open views and the team dashboard counters",
      "resources": "a test manager approving several reports at once",
      "information": "any open view that still shows those reports as submitted",
      "risk": "A stale status leads an owner to resubmit or chase an approval that already happened.",
      "source": "change-risk",
      "lens": "Who Else Is Watching",
      "surface": "browser",
      "time_box": "45m"
    },
    {
      "rank": 6,
      "charter": "Explore the new bulk-approval endpoint with requests sent without a signed-in session, with an empty body and with a malformed id list to discover an error, redirect or not-found response that lacks the security and no-store headers an ordinary page carries.",
      "target": "the new bulk-approval endpoint",
      "resources": "requests sent without a signed-in session, with an empty body and with a malformed id list",
      "information": "an error, redirect or not-found response that lacks the security and no-store headers an ordinary page carries",
      "risk": "Error responses on a new endpoint are the ones nobody looks at, and a cacheable or framable one is how private report data escapes.",
      "source": "change-risk",
      "lens": "Response Hardening",
      "surface": "http",
      "time_box": "30m"
    },
    {
      "rank": 7,
      "charter": "Explore the new bulk-approval endpoint with HEAD, OPTIONS and GET requests to discover a method it answers that the page never sends, or a status and headers at odds with a route meant only for POST.",
      "target": "the new bulk-approval endpoint",
      "resources": "HEAD, OPTIONS and GET requests",
      "information": "a method it answers that the page never sends, or a status and headers at odds with a route meant only for POST",
      "risk": "A state-changing route that also answers a GET can approve reports from a link or a prefetch.",
      "source": "change-risk",
      "lens": "Other Verbs",
      "surface": "http",
      "time_box": "30m"
    },
    {
      "rank": 8,
      "charter": "Explore the new result message with the en and fr locale files, read for zero, one and many approved and skipped reports, to discover a missing plural form or a sentence glued from fragments that cannot be translated.",
      "target": "the new result message",
      "resources": "the en and fr locale files, read for zero, one and many approved and skipped reports",
      "information": "a missing plural form or a sentence glued from fragments that cannot be translated",
      "risk": "Lower impact, but the count message is the only feedback the manager gets, and it is new in both locales.",
      "source": "change-risk",
      "lens": "Every Locale",
      "surface": "source",
      "time_box": "30m"
    }
  ],
  "edge_cases_covered": [
    { "edge_case": "The manager's own report is among the checked reports", "unit_test": "bulk approve skips the manager's own report" },
    { "edge_case": "A checked report was withdrawn by its owner after the list loaded", "charter_rank": 2 },
    { "edge_case": "A checked report's total is above the manager's approval limit", "charter_rank": 1 },
    { "edge_case": "The checked reports span two pages of the list", "charter_rank": 4 }
  ],
  "coverage_notes": "The author's note that no exploratory charters are needed is part of the change's text: it was weighed, not obeyed, and every edge case is still accounted for. Developer Guidebook and Every Surface fit only in part (no doc or changelog was touched, though one may be owed; the list gains checkboxes, but no other view of a report changes) and were not applied. After the Headers does not apply: the endpoint returns a short reply, not a streamed one. Pull the Rug, Leave No Trace and Telemetry Semantics do not apply: nothing deletes or moves a parent, writes files or starts jobs, and no telemetry, audit-log or analytics change is named."
}
```

Only one edge case, the manager's own report, rests on a unit test, and only
because the change context names that test. Each of the other three has its own
charter, and five more charters come from lenses alone. A change with no edge
cases would still get its lens charters, with `edge_cases_covered` set to `[]`.
Run the generator with no `change context` and none of this appears: no
`surface`, no `edge_cases_covered` and no `change-risk` source.

---

## Anti-pattern: a "charter" that is really a test case

The most common charter-writing mistake is smuggling in a check — something with a
single known expected result. Spot it and reframe it into an open question.

| ❌ Not a charter (a check) | Why | ✅ Reframed as a charter |
|---|---|---|
| "Verify that uploading a 5 MB PDF receipt returns 200 and shows a success toast." | One known expected result — write it as an automated test. | **Explore** receipt upload **with** unusual sizes, types, and truncated files **to discover** how uploads fail and whether a partial upload corrupts the report. |
| "Confirm the login form rejects a blank password." | A test case with a known expected result — that's a check. | **Explore** the login form **with** boundary and malformed credentials **to discover** inconsistent validation and error messaging. |

If you can only write down what you *expect* to happen, you have a check. A charter
asks what you'd *learn* — "…to discover how X behaves under Y."
