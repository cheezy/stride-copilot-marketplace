---
name: oracles
description: Use when you have observed a result during exploration and need to decide whether it is a defect, a known-bad-but-expected behavior, or acceptable. This skill supplies oracle strategies — Never/Always rules, alternative-resource consistency checks, and approximations for when the exact right answer is unknowable — plus the HTSM quality-criteria checklist for deriving Never/Always statements. Invoked by the exploratory-testing orchestrator, the explorer subagent, and the stride-exploratory-testing-explore skill whenever a probe produces a result that must be judged. Copilot port of the upstream oracles skill.
skills_version: "1.0"
---

# oracles

An **oracle** is a heuristic for recognizing a problem when you see one. Exploration constantly produces results no one pre-answered — "the report shows 47, is that right?" — and every such result needs an oracle to judge it. Oracles are **fallible**: they suggest that something is *worth questioning*, not that it is provably wrong. A spec is one oracle among many; this skill supplies the others, for the (frequent) case where no spec settles the question.

## The judgment this skill supports

For each observed result, classify it:

- **Defect** — it violates a Never/Always rule or a consistency oracle, with no justification. Report it.
- **Known-bad-but-expected** — it violates an oracle but is a *documented* limitation, an accepted trade-off, or an already-tracked issue. Note it and move on; don't re-report noise.
- **Acceptable** — it holds against every oracle you applied. Keep exploring.

When two oracles disagree (the product matches its spec but violates user expectations), that *conflict* is itself a finding worth raising — often the spec is wrong.

## Never / Always rules

The fastest oracle is an **invariant**: something the system should *never* do, or *always* do. Violations are strong bug signals because they need no reference to compute.

- *Never* lose committed data. *Never* charge a card twice for one action. *Never* expose one tenant's data to another.
- *Always* leave the user a next step. *Always* report an error in terms the user can act on. *Always* return to a consistent state after an interruption.

State the Never/Always for the target before you explore it; then every probe is also a check of those invariants. The quality-criteria checklist below is how you *generate* Never/Always statements systematically.

## Alternative resources (consistency oracles)

When there's no invariant to check, judge the result by **consistency with something else**. Ask "is this result consistent with…":

| Resource | The result should be consistent with… |
|---|---|
| **Internal consistency** | itself and the rest of the product — same term, same format, same rules everywhere. |
| **History** | how the product behaved before — an unexplained change from prior behavior is suspicious. |
| **Comparable products** | how similar features or competing products solve the same problem. |
| **Standards & references** | specs, RFCs, style guides, regulations, and domain references that apply. |
| **Claims** | what the docs, UI copy, marketing, and stakeholders say it does. |
| **User expectations** | what a reasonable user would expect — the "principle of least astonishment". |
| **Purpose** | the product's intended use — a result that defeats the point is a problem even if "correct". |

No single resource is authoritative; the more of them a result violates, the more confident the bug.

## Approximations — when the exact right answer is unknowable

Sometimes you cannot compute the one correct answer (complex domain logic, non-deterministic output, floating point, generated content). Judge it *approximately*:

- **Evaluate against a range** — the answer may be unknown, but its *bounds* are known. A tax can't be negative or exceed the total; a percentage sits in [0, 100]; a duration is positive. Flag anything outside the plausible range. *(Use this for complex-domain output whose exact value you can't recompute.)*
- **Evaluate characteristics** — don't check the exact value; check *properties* that must hold. A sort is monotonic; a shuffle preserves the multiset; shares sum to 100%; a round-trip preserves length. *(Use this for non-deterministic output — the value varies run to run, but the properties don't.)*
- **Invert the result** — reverse the operation and check you recover the input. Encode→decode, export→import, create→read, zip→unzip should round-trip to the original.
- **Select extreme conditions** — choose inputs where the correct answer *is* knowable: the empty case, the identity element, a single item, the maximum. The general answer may be opaque, but the extremes are checkable.

## Adapter Is Not the Wire

Some tests never open a socket. They pass the request to the app through an **in-process test adapter** — a test connection, a mock transport, a helper that calls the router directly — and read back the response the app assembled. That shows what the app built, whole, and nothing of what a real server does once the status line and headers have gone out. For four kinds of behaviour, a result seen only through an adapter is a *claim* to check, not an observation:

- **streamed or chunked responses** — what reaches the client when the source fails part-way through;
- **`HEAD` requests** — whether the reply carries the headers and no body;
- **connection aborts** — what each side does when the other drops the connection mid-response;
- **`Content-Length`** — whether the length the server declares matches the bytes it sends.

Check the claim on a real server: the authorized non-production target, at a host you were given, with `curl -q -sS -i` through `execute`. This oracle grants no new reach, and it never needs one. When you cannot check it, record the wire claim under `debrief.unknown`, never under `found`, and file no bug on it. It does not fire on a charter whose responses are none of the four: an ordinary buffered response seen through an adapter is judged by the other oracles as usual.

*Example:* a report export passes its test through the adapter, with a `200` and the whole file. Served for real, the file streams after the `200` is already sent, so a source that breaks part-way leaves the client a `200` and a short file that looks finished. The adapter's pass says nothing about that window. Request the export with `curl -q -sS -i` against the running app on a listed host, or write "streamed export not observed on the wire" under `debrief.unknown`. The **After the Headers** lens in the `heuristics` skill shapes the probe; this oracle judges what it shows.

## Two Decision Sites

Sometimes the **client and the server each decide the same thing** — whether a user may act, how much of a quota is left, what kind of file this is, which plan an account is on. Then the two sites must **agree in every state**. A disagreement is a finding whichever site is right: the user is offered an action the server refuses, or kept from one it would accept.

- Name the states that can move the decision — signed out, one below a limit, at it, past it, changed from another session, a page left open while the server's state moved on — and check both sites in each.
- A client that matches the server in every state you tried is **Acceptable**. One state where they part is a **Defect**, and the server's answer is the one the client must follow.

*Example:* a quota has one slot left and a second session takes it; the first session's add button stays enabled, and pressing it gets a vague server error. Or a file picker accepts a type the server then rejects. Each is two decision sites disagreeing. The **Shadow Decision** lens in the `heuristics` skill shapes the probe; this oracle judges what it shows.

## Quality-criteria checklist → Never/Always

To surface Never/Always rules systematically, walk the **quality criteria** (the "-ilities" from the Heuristic Test Strategy Model). For each, ask "what must this feature *never* do, and *always* do?"

| Criterion | Prompt | Example Never/Always |
|---|---|---|
| **Capability** | Does it do what it claims, completely? | *Never* silently drop a requested operation; *always* do what the button says. |
| **Reliability** | Does it hold up over time, load, and failure? | *Never* lose committed data on a crash; *always* recover to a consistent state after an interruption. |
| **Usability** | Can a real user succeed without surprise? | *Never* leave the user stuck with no next step; *always* phrase errors in terms the user can act on. |
| **Scalability** | Does it hold as volume grows? | *Never* degrade to failure within the expected growth range; *always* bound resource use. |
| **Security** | Does it protect data and access? | *Never* store secrets in cleartext; *always* enforce authorization on every access, server-side. |
| **Performance** | Is it responsive enough? | *Never* block the UI on a long operation with no feedback; *always* respond within the stated budget. |
| **Accessibility** | Can everyone use it? | *Never* convey meaning by color alone; *always* expose controls and state to assistive technology. |

Sweep these criteria over the target and you get a Never/Always set that turns vague "does this seem OK?" into concrete, checkable invariants.

## Safety of oracle examples

Security-flavored Never/Always examples (e.g. "never store secrets in cleartext") are illustrative — they **must not embed real secrets, tokens, or credentials**; use placeholders. And oracle evaluation is about judging results from **a system you are authorized to test** — this guidance never encourages probing or comparing against systems the user has no permission to test. Checking wire behaviour on a real server is a probe like every other: it reaches only the authorized non-production target and its listed hosts, and *Adapter Is Not the Wire* grants no new reach.

## Handing off

The `chartering` skill sets the mission and the `heuristics` skill generates the probes; this skill judges what those probes reveal. Known-bad-but-expected observations are recorded but not re-reported.

A finding you classify as a **Defect** does not go straight into the report. Hand it to the **`bug-advocacy`** skill first: it owns the work between "an oracle says this is wrong" and "a stakeholder can act on this" — Replicate, Isolate, Maximize, Generalize, Externalize, And say it clearly, plus the severity rubric that makes ratings comparable across sessions. From there the write-up flows into the session notes and debrief (the `session` skill).
