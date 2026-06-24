---
name: launchdarkly-fundamentals
description: Use when working with LaunchDarkly feature flags at the conceptual level — what flags and variations are, the evaluation-context model, why every evaluation must pass a safe default value, the streaming-vs-polling data model and local evaluation, and the flag lifecycle with the design-for-removal principle. This is the SDK-agnostic base that the per-SDK skills (Java, TypeScript Node/client/React) build on; it contains no SDK-specific code.
---

# LaunchDarkly Fundamentals and Flag Lifecycle

This skill is the conceptual foundation for the rest of the LaunchDarkly plugin.
It explains the model that **every** SDK shares so the per-SDK skills don't have
to repeat it. It is deliberately **SDK-agnostic**: there is no Java or
TypeScript code here. When you need concrete SDK calls, use the matching
per-SDK skill; when you need to reason about *what a flag is*, *what a context
is*, or *when a flag should be removed*, use this one.

> **Verify, don't invent.** LaunchDarkly's product and SDK surface evolve.
> Treat the concepts here as the stable mental model, but confirm specific
> method names, signatures, and option keys against the current official
> LaunchDarkly SDK documentation before writing code — never reconstruct an SDK
> API from memory.

## Feature flags and variations

A **feature flag** is a named decision point in your code. Instead of hardcoding
behavior, your code asks LaunchDarkly which **variation** of the flag applies for
the current situation, and branches on the answer. Flipping the flag in the
LaunchDarkly dashboard changes behavior in running applications without a
deploy.

Every flag has a fixed set of **variations** — the possible values it can return:

- **Boolean flags** have exactly two variations, `true` and `false`. These are
  the common "is this feature on?" toggles.
- **Multivariate flags** have more than two variations of a single type. The
  variation type can be string, number, or JSON. Use these for things like
  choosing one of several algorithms, copy variants, or structured
  configuration blobs.

Targeting rules on the flag (configured in LaunchDarkly, not in code) decide
*which* variation a given evaluation receives. Your code's job is only to
**evaluate** the flag and act on the result.

## Evaluation contexts

LaunchDarkly evaluates a flag *for a context*. A **context** is a data object
describing the entity the evaluation is about — historically this was always a
"user," but the modern model generalizes it.

- **Context kind** — the category of the entity. The most common kind is
  `user`, but you can define other kinds such as `organization`, `device`,
  `account`, or `request`. Kinds let you target on the dimension that actually
  matters for a given flag.
- **Built-in attributes** — every context has `kind`, `key`, `name`, and
  `anonymous`. The `key` is the stable unique identifier for that context
  within its kind; it's what LaunchDarkly uses for consistent
  percentage-rollout bucketing.
- **Custom attributes** — arbitrary additional data used by targeting rules.
  Attribute values can be strings, booleans, numbers, arrays, or JSON objects
  (for example `plan: "enterprise"`, `betaTester: true`, `region: "us-east"`).
- **Multi-contexts** — a single evaluation can combine several context kinds at
  once (for example a `user` *and* their `organization` *and* their `device`).
  This lets one flag target on attributes drawn from multiple entities in the
  same call.

Design targeting around context **attributes** rather than enumerating
individual keys wherever you can — attribute-based rules survive as your user
base changes, and they keep personally identifying detail out of per-key target
lists.

## Evaluation and the safe default value

**Every flag evaluation passes a default value, and you must always supply one.**
The default value is the last argument to the evaluation call across all
LaunchDarkly SDKs. It is *not* a value configured in the LaunchDarkly UI — it
lives in your code and is the value the SDK returns when it cannot give you a
real answer.

The SDK returns your default value (and reports a `null` variation index)
whenever it cannot evaluate the flag, including when:

- the SDK is **not yet initialized** or has **lost its connection** to
  LaunchDarkly (the evaluation reason is `ERROR` with error kind
  `CLIENT_NOT_READY`);
- **no valid context** was supplied (error kind `USER_NOT_SPECIFIED`);
- the flag **doesn't exist** or the SDK otherwise hits an error.

Because the default is what ships during an outage, a missing flag, or a
misconfiguration, **the default must be the safe, conservative choice** — the
behavior you'd want the world to fall back to if LaunchDarkly were completely
unreachable. A default that turns *on* an unfinished, risky, or
not-yet-authorized code path means an outage silently exposes that behavior to
everyone. The safe default for a new feature is almost always "feature off."

> **Principle:** Never describe, scaffold, or review a flag evaluation that
> omits a default value, and always sanity-check that the chosen default is the
> safe branch.

### Evaluation reasons

When you ask the SDK *why* it returned a variation, it gives an evaluation
reason. The reason kinds are:

| Reason kind | Meaning |
|---|---|
| `OFF` | Targeting is off; the flag returned its configured off value. |
| `FALLTHROUGH` | The context matched no specific target or rule, so the flag's default ("fallthrough") rule applied. |
| `TARGET_MATCH` | The context key was individually targeted. |
| `RULE_MATCH` | The context matched a targeting rule (includes the rule index/id). |
| `PREREQUISITE_FAILED` | A prerequisite flag's condition was not met. |
| `ERROR` | The SDK could not evaluate the flag; your code's default value was returned. |

Reasons are mainly a diagnostic and experimentation aid — but note that an
`ERROR` reason is exactly the case where your safe default value carries the
behavior.

## The SDK data model: streaming, polling, and local evaluation

LaunchDarkly SDKs keep flag data current using one of two transports:

- **Streaming** — the SDK holds a persistent connection and LaunchDarkly
  **pushes** updates the instant a flag changes. This is the default and
  recommended mode for long-running server applications because changes take
  effect in near real time.
- **Polling** — the SDK periodically **asks** LaunchDarkly for changes at a
  fixed interval. It trades update latency for fewer open connections, which
  suits some constrained or short-lived environments.

**Local evaluation** is the key performance idea on the server side: rather than
making a network round trip per flag check, the SDK receives flag rules and
keeps them in an in-memory cache (refreshed via streaming or polling). Each
`variation` call is then evaluated **locally, in-process**, so it is effectively
instantaneous and does not depend on per-call network availability. (How that
cached ruleset is obtained differs between client-side and server-side SDKs —
see below.)

## Client-side vs. server-side evaluation

LaunchDarkly distinguishes SDKs by the **trust level of the environment** they
run in. This determines how evaluation works and which credential is used — and
the per-SDK skills depend on getting this right.

- **Server-side SDKs** run in trusted environments (your backend). They download
  the **complete ruleset** for the environment and **evaluate flags locally**
  using that cached ruleset. They authenticate with an **SDK key**, which grants
  read access to all flag data in its environment and **must be kept secret**
  (treat it like a password; rotate it if exposed).
- **Client-side SDKs** run in untrusted environments (browsers, mobile, desktop)
  where code and memory can be inspected. They **cannot** download the full
  ruleset — that would leak targeting rules and other contexts' data. Instead
  they **delegate evaluation to LaunchDarkly** for one specific context and
  receive back only that context's flag values. They authenticate with a
  **client-side ID**, which is not a secret (it's designed to be exposed in
  client code).
- **Edge SDKs** run in CDN/edge environments and evaluate locally against flag
  data written to the edge provider's store by a LaunchDarkly integration.

> **Security:** Never put a server-side **SDK key** into client/browser code, and
> never treat a **client-side ID** as a substitute for the SDK key. Confusing the
> two either leaks all flag data or breaks evaluation.

## The flag lifecycle and designing for removal

A flag is not forever. Decide up front whether a flag is **temporary** or
**permanent**, because that decision is what tells you when to remove it.

- **Temporary flags** have a limited lifespan — release management, gradual
  rollouts, experiments, migrations, and interop testing. **Once the flag has
  served its purpose, it should be removed from the codebase.**
- **Permanent flags** intentionally live for the life of a feature — entitlements,
  load-shedding/kill switches, custom branding, accessibility toggles. They stay,
  but they should still be clearly marked as permanent so nobody mistakes them
  for stale debt.

LaunchDarkly reports **flag status** to help you spot removable flags:

- **New** — created recently and never evaluated.
- **Active** — currently being evaluated.
- **Launched** — serving the *same* variation to every context (a gradual
  rollout has finished; the flag no longer changes behavior).
- **Inactive** — not evaluated for at least seven days.

A flag also moves through **lifecycle stages** across environments: *live* →
*ready for code removal* → *ready to archive* → *archived* (and *deprecated*).
A **temporary** flag that is **Launched** or **Inactive** is a prime candidate
for code removal. Temporary flags that linger — for example, temporary flags
older than ~90 days still sitting Inactive or Launched — are **stale flags** and
are exactly the technical debt this plugin exists to prevent.

### Design for removal from day one

The single most important lifecycle habit: **introduce every temporary flag with
a removal plan already in mind.** Concretely:

- Decide and record whether the flag is temporary or permanent *when you create
  it*.
- Structure the flag-gated code so the flag is read in **one place** behind a
  clear boundary, not scattered across the codebase — removal then means
  deleting one branch and inlining the winning path. (The code-structuring skill
  in this plugin covers how to do that; the testing skill covers exercising both
  branches.)
- Treat "remove the temporary flag and its dead branch" as part of finishing the
  feature, not as optional cleanup.

A flag that was easy to add but hard to remove is a flag that becomes permanent
technical debt by accident. Designing for removal up front is what keeps a flag
system healthy.

## Principles summary

- A flag returns one of its fixed **variations**; targeting rules pick which.
- Evaluate flags **for a context**; prefer attribute-based targeting over
  per-key lists; contexts have kinds and can be combined as multi-contexts.
- **Always pass a default value**, and make it the **safe** branch — it's what
  ships during an outage or misconfiguration.
- Server-side SDKs evaluate **locally** from a full ruleset (secret **SDK key**);
  client-side SDKs get **delegated** evaluation for one context (non-secret
  **client-side ID**). Streaming pushes updates; polling asks on an interval.
- Classify each flag **temporary or permanent**, keep it behind a single
  removable boundary, and **plan its removal from day one** to avoid stale-flag
  technical debt.
