---
name: launchdarkly-flag-removal
description: Use when retiring a temporary LaunchDarkly flag that has served its purpose — collapse the code to the explicitly chosen winning variation. Inlines the winner, deletes the losing branch, removes branch-only (dead) tests while keeping behavior tests, deletes the flag-key constant and its import, and reports any flag usage it cannot safely collapse for human follow-up instead of guessing. Assumes the single-boundary structure from the launchdarkly-flag-structure skill. Given a flag key and the winning variation, make removal a mechanical, low-risk edit.
---

# LaunchDarkly Flag Removal

Close the flag lifecycle: remove a temporary flag that has served its purpose by
**collapsing the code to the winning variation**. When the flag was structured
per the `launchdarkly-flag-structure` skill (one read boundary, a stable seam, a
named constant), removal is mechanical and low-risk. When it was not, this skill
**reports the unsafe usage rather than editing it**.

## Inputs

| Input | Required | Description |
|---|---|---|
| flag key | yes | The flag key to remove, e.g. `new-checkout`. |
| winning variation | yes | The variation the code should collapse to (e.g. `true`/`false` for a boolean, or a named multivariate value). This is the explicitly chosen winner — never guess it. |

## What to do

### Step 1: Parse and validate the inputs

- One input is the **flag key**, the other is the **winning variation**.
- If either is missing, stop with:
  `flag removal: a flag key and the winning variation are required (e.g. new-checkout true)` and change nothing.
- The winning variation is **mandatory and explicit** — never infer it from the
  flag's current default or rollout state.

### Step 2: Apply the structuring skill

Apply the `launchdarkly-flag-structure` skill so you recognize the canonical
single-boundary seam (named constant, factory/resolver read boundary, two
implementations behind one interface) and can collapse it correctly.

### Step 3: Find every reference

Find all references to the flag — both the **constant** and any **raw key
string** and the **read boundary** (search the codebase for both `<FLAG_CONSTANT_NAME>`
and the raw `<flag-key>`).

Classify each hit:
- **Single-boundary seam** (the `variation` read sits in one factory/resolver,
  behind the constant) → safe to collapse automatically (Step 4).
- **Anything else** — a `variation` call at a scattered call site, a raw
  string-literal key, or a reference in config/docs → **non-conforming**; do not
  edit it. Collect it for the Step 5 report.

### Step 4: Collapse conforming seams to the winner

For each single-boundary seam:

1. **Delete the losing implementation** (the branch the winner replaces).
2. **Inline the winner at the read boundary** — replace the `variation` call and
   its branch with the winning implementation directly, and drop the now-unused
   `context` plumbing that only existed for the read.
3. **Delete the flag-key constant** and remove any import that referenced only it.
4. **Remove branch-only tests** — delete tests that existed *solely* to exercise
   the now-dead branch (e.g. the parameterized case for the losing value). **Keep
   behavior tests** that assert observable behavior still in effect; rewrite a
   parameterized both-states test down to the winning behavior rather than
   deleting it wholesale.

The winner MUST be the explicitly supplied winning variation — which should also
be the safe-default branch — so the collapse never silently changes behavior.

### Step 5: Report what could not be collapsed

Print a clear report of every non-conforming usage you did **not** edit, with
file:line and why, for human follow-up — for example:

```
flag removal: collapsed 1 seam to the winning branch.
Could NOT safely collapse (left untouched — please handle manually):
  - src/legacy/Report.java:88  raw "new-checkout" string read, not behind the seam
  - config/flags.yaml:12       flag referenced in config
  - docs/checkout.md:40        flag referenced in documentation
```

Never silently edit a scattered read or a config/doc reference — surface it.

## Example — Java (before → after)

**Before** (scaffolded seam, winning variation = `true` / NewCheckout):

```java
public final class CheckoutFactory {
  private final LDClient ld;
  public CheckoutFactory(LDClient ld) { this.ld = ld; }
  public Checkout forContext(LDContext context) {
    boolean useNew = ld.boolVariation(FlagKeys.NEW_CHECKOUT, context, false);
    return useNew ? new NewCheckout() : new LegacyCheckout();
  }
}
```

**After** (winning variation `true` / NewCheckout): `LegacyCheckout` deleted,
`FlagKeys.NEW_CHECKOUT` deleted, the parameterized both-states test rewritten to
assert only the `NewCheckout` behavior:

```java
public final class CheckoutFactory {
  public Checkout forContext(LDContext context) {
    return new NewCheckout();
  }
}
```

(If `context` becomes entirely unused after removal, drop it from the signature
and its callers too.)

## Example — TypeScript (before → after)

**Before** (winning variation = `true` / NewCheckout):

```typescript
export async function resolveCheckout(ld: LDClient, context: LDContext): Promise<Checkout> {
  const useNew = await ld.variation(NEW_CHECKOUT, context, false);
  return useNew ? new NewCheckout() : new LegacyCheckout();
}
```

**After** (winning variation `true` / NewCheckout): `LegacyCheckout` and the
`NEW_CHECKOUT` constant/import deleted, the `it.each` both-states test reduced to
the winning case:

```typescript
export function resolveCheckout(): Checkout {
  return new NewCheckout();
}
```

## Pitfalls

- **Don't silently edit non-single-boundary reads.** Scattered reads, raw string
  keys, and config/doc references are reported for human follow-up, never
  auto-edited.
- **Don't remove behavior tests.** Only delete tests that solely exercised the
  dead branch; keep (or down-rewrite) tests asserting behavior still in effect.
- **Don't leave a dangling constant or import.** Remove the flag-key constant and
  any import that referenced only it.
- **Don't guess the winner.** Collapse to the explicitly supplied winning
  variation (which is the safe-default branch), never an inferred one.
