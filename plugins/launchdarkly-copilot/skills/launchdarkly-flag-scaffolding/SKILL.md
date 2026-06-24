---
name: launchdarkly-flag-scaffolding
description: Use when scaffolding a new LaunchDarkly flag-gated code path in Java or TypeScript. Generates a single-boundary flag-read seam, stub on/off behaviors behind it, a named flag-key constant with a removal note, and a test file covering BOTH flag states via the SDK TestData source. Driven by the launchdarkly-flag-structure and launchdarkly-testing skills. Given a flag key, a target language (java or typescript), and an optional description, produce removable-by-design, both-states-tested code.
---

# LaunchDarkly Flag Scaffolding

Generate flag-gated code that is **removable by design** and **tested in both
states** from the start. Given a flag key, a target language, and an optional
description, produce a single-boundary flag-read seam, stub on/off behaviors
behind that seam, a named flag-key constant with a removal note, and a test file
that exercises BOTH the flag-on and flag-off branches with no network.

The generated structure follows the `launchdarkly-flag-structure` skill and the
generated tests follow the `launchdarkly-testing` skill — apply both so the
output matches the canonical patterns.

## Inputs

| Input | Required | Description |
|---|---|---|
| flag key | yes | The LaunchDarkly flag key, e.g. `new-checkout`. Used to derive a constant and the variation call. |
| language | yes | Target language. Only `java` and `typescript` are supported. |
| description | no | A short phrase naming the gated behavior (e.g. "new checkout flow"); used in comments and class names. |

## What to do

### Step 1: Parse and validate the inputs

- If the **flag key is missing/empty**, stop with a clear error:
  `flag scaffolding: a flag key is required (e.g. new-checkout java)` and do not generate anything.
- Normalize the language to lower case. If it is **not** `java` or `typescript`,
  stop with: `flag scaffolding: unsupported language '<value>' — supported: java, typescript` and generate nothing.
- Derive a constant name from the flag key (upper snake case: `new-checkout` → `NEW_CHECKOUT`) and a PascalCase behavior name from the description or flag key (`NewCheckout`).

### Step 2: Apply the driving skills

Apply the `launchdarkly-flag-structure` and `launchdarkly-testing` skills so the
generated seam and tests match those patterns exactly. Do not improvise a
different structure.

### Step 3: Generate the files

Generate the seam + stubs + constant + removal note, and a matching both-states
test file. Follow these rules (from the driving skills):

- **Single read boundary:** the flag is read in exactly one place (a factory /
  resolver), never at scattered call sites.
- **Named constant + removal note:** the flag key is a named constant with a
  comment recording that it is temporary and which branch is the winning,
  safe-default branch.
- **Safe default:** the `variation` call's default is `false` / the legacy
  branch, so an error or outage keeps the safe behavior.
- **Both-states test:** the generated test drives the flag on AND off through the
  SDK **TestData source** (no live LaunchDarkly, no real SDK key).

### Step 4: Security

- Generated code must read the SDK key from **environment/config**, never a
  hardcoded literal.
- **Server scaffolds (Java, TypeScript-Node) use a server SDK key; browser/React
  scaffolds use a client-side ID.** This skill emits a server-side seam by
  default; for a browser target, follow the `launchdarkly-typescript-client`
  skill and substitute the client-side ID and the `variation`-without-context
  form.

## Example output — Java

For flag key `new-checkout`, language `java`, description "new checkout flow":

```java
// FlagKeys.java
public final class FlagKeys {
  /** TEMPORARY (remove after rollout): winning branch = NEW checkout. Safe default = false (legacy). */
  public static final String NEW_CHECKOUT = "new-checkout";
  private FlagKeys() {}
}

// Checkout.java — the stable seam
public interface Checkout { Receipt process(Cart cart); }
public final class LegacyCheckout implements Checkout { /* off-branch */ }
public final class NewCheckout implements Checkout { /* on-branch */ }

// CheckoutFactory.java — THE single read boundary
public final class CheckoutFactory {
  private final LDClient ld;
  public CheckoutFactory(LDClient ld) { this.ld = ld; }
  public Checkout forContext(LDContext context) {
    boolean useNew = ld.boolVariation(FlagKeys.NEW_CHECKOUT, context, false); // false = safe default
    return useNew ? new NewCheckout() : new LegacyCheckout();
  }
}
```

```java
// CheckoutFactoryTest.java — both states, no live LD
@ParameterizedTest
@ValueSource(booleans = {true, false})
void picksImplementationForFlagState(boolean flagOn) throws Exception {
  TestData td = TestData.dataSource();
  td.update(td.flag(FlagKeys.NEW_CHECKOUT).booleanFlag().variationForAll(flagOn));
  try (LDClient client = new LDClient("test-key", new LDConfig.Builder().dataSource(td).build())) {
    Checkout checkout = new CheckoutFactory(client).forContext(LDContext.builder("u").build());
    assertEquals(flagOn ? NewCheckout.class : LegacyCheckout.class, checkout.getClass());
  }
}
```

## Example output — TypeScript

For flag key `new-checkout`, language `typescript`, description "new checkout flow":

```typescript
// flag-keys.ts
/** TEMPORARY (remove after rollout): winning branch = new checkout. Safe default = false (legacy). */
export const NEW_CHECKOUT = 'new-checkout';

// checkout.ts — the stable seam
export interface Checkout { process(cart: Cart): Promise<Receipt>; }
export class LegacyCheckout implements Checkout { /* off-branch */ }
export class NewCheckout implements Checkout { /* on-branch */ }

// checkout-factory.ts — THE single read boundary
import { LDClient } from '@launchdarkly/node-server-sdk';
import { NEW_CHECKOUT } from './flag-keys';
export async function resolveCheckout(ld: LDClient, context: LDContext): Promise<Checkout> {
  const useNew = await ld.variation(NEW_CHECKOUT, context, false); // false = safe default
  return useNew ? new NewCheckout() : new LegacyCheckout();
}
```

```typescript
// checkout-factory.test.ts — both states, no live LD
import { init } from '@launchdarkly/node-server-sdk';
import { TestData } from '@launchdarkly/node-server-sdk/integrations';
import { resolveCheckout, NewCheckout, LegacyCheckout } from './checkout-factory';
import { NEW_CHECKOUT } from './flag-keys';

it.each([[true, NewCheckout], [false, LegacyCheckout]])(
  'flag=%s resolves the right implementation',
  async (flagOn, expected) => {
    const td = new TestData();
    td.update(td.flag(NEW_CHECKOUT).booleanFlag().variationForAll(flagOn));
    const client = init('test-key', { updateProcessor: td.getFactory() });
    await client.waitForInitialization({ timeout: 10 });
    const checkout = await resolveCheckout(client, { kind: 'user', key: 'u' });
    expect(checkout).toBeInstanceOf(expected);
    await client.close();
  },
);
```

## Pitfalls

- **Don't scatter the flag read.** Generate exactly one read boundary; callers
  depend on the seam.
- **Don't generate a one-branch test.** The test must assert both flag-on and
  flag-off (the off branch is the safe default).
- **Don't hardcode SDK keys.** Generated code reads the key from env/config;
  tests use the offline TestData source with a fake key.
