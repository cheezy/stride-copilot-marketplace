---
name: launchdarkly-flag-structure
description: Use when writing or reviewing LaunchDarkly flag-gated code and deciding HOW to structure it so the flag is easy to remove later. Teaches the single-boundary read rule, putting the two behaviors behind a stable seam (interface/strategy or a thin wrapper), naming flag keys as searchable constants, leaving a removal note, and keeping the on-branch and off-branch independently testable. Includes one Java and one TypeScript illustration. For SDK evaluation specifics see the launchdarkly-java-sdk / launchdarkly-typescript-node / launchdarkly-typescript-client skills; for concepts and the design-for-removal principle see launchdarkly-fundamentals.
---

# Structuring Removable Flag-Gated Code

The single biggest long-term cost of feature flags is **removal**. A flag whose
reads are sprinkled across dozens of call sites becomes a risky archaeology
project to retire, so teams leave temporary flags in place for months — exactly
the stale-flag technical debt the `launchdarkly-fundamentals` skill warns about.
This skill is about *structure*: organize flag-gated code so that removing the
flag later is a **mechanical, low-risk edit**, not a hunt.

This structuring is consumed by the plugin's scaffolding command, removal
command, and review agent — they all assume the patterns below.

## Rule 1 — Read each flag at a single boundary

Evaluate a given flag in **exactly one place per module/service**, capture the
result in a local, and branch on that. Do **not** call `variation` at many
scattered call sites.

- **Why:** one read site means one place to find, one place to delete. Scattered
  reads mean every call site is a removal hazard and the branches drift apart.
- A flag used in several modules still gets **one read boundary per module** —
  not one read per function.

## Rule 2 — Put the two behaviors behind a stable seam

Express the on-behavior and off-behavior as two implementations of the **same
interface** (a strategy), or hide the branch inside a **thin wrapper** function.
Callers depend on the seam, not on the flag.

- **Why:** when the flag is removed, you delete the losing implementation and
  wire the seam directly to the winner. Callers don't change at all.
- The two implementations must be **independently testable** — neither should
  reach back through the other or share mutable branch state.

## Rule 3 — Name flag keys as searchable constants

Define each flag key **once** as a named constant; never pass a raw string
literal to `variation`.

- **Why:** a constant is greppable (find every reference instantly at removal
  time) and typo-proof. `"new-chekout"` as a literal silently returns the default
  forever.

## Rule 4 — Leave a removal note

Next to the flag constant, record that the flag is temporary, what the **winning
(safe-default) branch** is, and the removal trigger. The safe default and the
intended winner should be the same branch, so collapsing to it can never expose
the unfinished path.

## Java illustration

Single read boundary, two strategies behind one interface, a named constant, and
a removal note:

```java
// FlagKeys.java — searchable constants + removal notes
public final class FlagKeys {
  /** TEMPORARY (remove after rollout): winning branch = NEW checkout. Safe default = false (legacy). */
  public static final String NEW_CHECKOUT = "new-checkout";
  private FlagKeys() {}
}

// Checkout.java — the stable seam
public interface Checkout {
  Receipt process(Cart cart);
}

public final class LegacyCheckout implements Checkout { /* off-branch */ }
public final class NewCheckout implements Checkout { /* on-branch */ }

// CheckoutFactory.java — THE single read boundary for this module
public final class CheckoutFactory {
  private final LDClient ld;

  public CheckoutFactory(LDClient ld) {
    this.ld = ld;
  }

  public Checkout forContext(LDContext context) {
    // false = safe default (legacy) — the only place the flag is read.
    boolean useNew = ld.boolVariation(FlagKeys.NEW_CHECKOUT, context, false);
    return useNew ? new NewCheckout() : new LegacyCheckout();
  }
}
```

`LegacyCheckout` and `NewCheckout` are tested directly, with no flag involved.
Only `CheckoutFactory` needs a flag-aware test (one case per branch).

## TypeScript illustration

Same shape — one read boundary, a thin wrapper returning the chosen
implementation, a constant, and a removal note:

```typescript
// flag-keys.ts — searchable constants + removal notes
/** TEMPORARY (remove after rollout): winning branch = new checkout. Safe default = false (legacy). */
export const NEW_CHECKOUT = 'new-checkout';

// checkout.ts — the stable seam
export interface Checkout {
  process(cart: Cart): Promise<Receipt>;
}

export class LegacyCheckout implements Checkout { /* off-branch */ }
export class NewCheckout implements Checkout { /* on-branch */ }

// checkout-factory.ts — THE single read boundary for this module
import { LDClient } from '@launchdarkly/node-server-sdk';
import { NEW_CHECKOUT } from './flag-keys';

export async function resolveCheckout(ld: LDClient, context: LDContext): Promise<Checkout> {
  // false = safe default (legacy) — the only place the flag is read.
  const useNew = await ld.variation(NEW_CHECKOUT, context, false);
  return useNew ? new NewCheckout() : new LegacyCheckout();
}
```

`LegacyCheckout` and `NewCheckout` are unit-tested directly; only
`resolveCheckout` needs the flag stubbed (e.g. the TestData source from the
per-SDK skill) once per branch.

## Mechanical removal

Because the flag lives behind one boundary and one constant, retiring it is a
fixed sequence — collapsing to the **winning (safe-default) branch**:

1. Grep the flag constant (`NEW_CHECKOUT`) to confirm it's referenced only at the
   single read boundary.
2. Delete the losing implementation (`LegacyCheckout`).
3. Replace the read boundary so it always returns the winner — inline
   `NewCheckout` and drop the `variation` call and the `context` plumbing it
   needed.
4. Delete the flag constant and its removal note; drop the now-dead branch tests.
5. Archive/remove the flag in LaunchDarkly.

No caller changes because callers only ever depended on the `Checkout` seam.

## Pitfalls

- **Don't scatter flag reads.** One read boundary per module; branch on a local,
  not on repeated `variation` calls.
- **Don't use raw string literals for flag keys.** Use named, searchable
  constants so removal can find every reference.
- **Don't entangle the branches.** The on and off implementations must be
  independently testable — no shared mutable branch state, no cross-calls.
- **Don't let the winner differ from the safe default.** Removal collapses to the
  safe-default branch; make that the intended winner so retirement can't expose
  the unfinished path.
