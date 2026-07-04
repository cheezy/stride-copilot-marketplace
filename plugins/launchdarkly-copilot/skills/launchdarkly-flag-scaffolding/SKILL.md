---
name: launchdarkly-flag-scaffolding
description: Use when scaffolding a new LaunchDarkly flag-gated code path in Java, TypeScript (Node), the browser (v4 client-side JS), or React (v4). Generates a single-boundary flag-read seam, stub on/off behaviors behind it, a named flag-key constant with a removal note, and a test file covering BOTH flag states (server targets via the SDK TestData source; browser/React via a mocked v4 client/hook — never the client-side key or a live service). Driven by the launchdarkly-flag-structure, launchdarkly-testing, and launchdarkly-typescript-client skills. Given a flag key, a target language (java, typescript, browser, or react), and an optional description, produce removable-by-design, both-states-tested code.
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
| language | yes | Target language. Supported: `java`, `typescript` (Node server), `browser` (v4 client-side JS), and `react` (v4 React). |
| description | no | A short phrase naming the gated behavior (e.g. "new checkout flow"); used in comments and class names. |

## What to do

### Step 1: Parse and validate the inputs

- If the **flag key is missing/empty**, stop with a clear error:
  `flag scaffolding: a flag key is required (e.g. new-checkout java)` and do not generate anything.
- Normalize the language to lower case. If it is **not** one of `java`,
  `typescript`, `browser`, or `react`, stop with:
  `flag scaffolding: unsupported language '<value>' — supported: java, typescript, browser, react` and generate nothing.
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
- **Server scaffolds (`java`, `typescript`) use a server SDK key; browser/React
  scaffolds (`browser`, `react`) use a client-side ID.** The `browser` and
  `react` targets emit the v4 client-side seam (see their examples below) and
  must read a **client-side ID** — never a server SDK key — from
  environment/config, following the `launchdarkly-typescript-client` skill
  (`createClient`/`client.start()` with no-context typed variation for browser;
  `createLDReactProvider` + typed hooks for React).

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

## Example output — Browser (v4 client-side JS)

For flag key `new-checkout`, language `browser`, description "new checkout flow".
The client is created **once** with the **client-side ID** (never a server key)
and the context is set at init, so the typed variation takes **no context
argument**.

```typescript
// flag-keys.ts
/** TEMPORARY (remove after rollout): winning branch = new checkout. Safe default = false (legacy). */
export const NEW_CHECKOUT = 'new-checkout';

// checkout.ts — the stable seam
export interface Checkout { render(): void; }
export class LegacyCheckout implements Checkout { /* off-branch */ }
export class NewCheckout implements Checkout { /* on-branch */ }

// bootstrap.ts — create ONE client with the CLIENT-SIDE ID, then start it
import { createClient } from '@launchdarkly/js-client-sdk';
const clientSideId = import.meta.env.VITE_LD_CLIENT_SIDE_ID; // client-side ID, never a server key
export const ldClient = createClient(clientSideId, { kind: 'user', key: 'context-key-123abc' });
ldClient.start();

// checkout-factory.ts — THE single read boundary
import type { LDClient } from '@launchdarkly/js-client-sdk';
import { NEW_CHECKOUT } from './flag-keys';
export function resolveCheckout(client: LDClient): Checkout {
  const useNew = client.boolVariation(NEW_CHECKOUT, false); // no context arg; false = safe default
  return useNew ? new NewCheckout() : new LegacyCheckout();
}
```

```typescript
// checkout-factory.test.ts — both states, no live LD, no client-side key
import { resolveCheckout, NewCheckout, LegacyCheckout } from './checkout-factory';
import { NEW_CHECKOUT } from './flag-keys';
import type { LDClient } from '@launchdarkly/js-client-sdk';

// Stub only the one client method the seam uses — no network, no real key.
const clientReturning = (value: boolean) =>
  ({ boolVariation: (key: string, def: boolean) => (key === NEW_CHECKOUT ? value : def) }) as unknown as LDClient;

it.each([[true, NewCheckout], [false, LegacyCheckout]])(
  'flag=%s resolves the right implementation',
  (flagOn, expected) => {
    expect(resolveCheckout(clientReturning(flagOn as boolean))).toBeInstanceOf(expected);
  },
);
```

## Example output — React (v4)

For flag key `new-checkout`, language `react`, description "new checkout flow".
The provider is created **once** at the app entry point with the **client-side
ID**; the flag is read in **one** custom hook (`useCheckout`) via the v4 typed
hook `useBoolVariation` — components call that hook, never `useBoolVariation`
directly.

```tsx
// flag-keys.ts
/** TEMPORARY (remove after rollout): winning branch = new checkout. Safe default = false (legacy). */
export const NEW_CHECKOUT = 'new-checkout';

// checkout.tsx — the stable seam + THE single read boundary
import { useBoolVariation } from '@launchdarkly/react-sdk';
import { NEW_CHECKOUT } from './flag-keys';

export function LegacyCheckout() { return <div>legacy checkout</div>; }
export function NewCheckout() { return <div>new checkout</div>; }

// Single boundary: one hook reads the flag; components consume this, not the SDK hook.
export function useCheckout(): React.ComponentType {
  const showNew = useBoolVariation(NEW_CHECKOUT, false); // false = safe default
  return showNew ? NewCheckout : LegacyCheckout;
}

export function Checkout() {
  const Impl = useCheckout();
  return <Impl />;
}

// app.tsx — create the provider ONCE with the CLIENT-SIDE ID (never a server key)
import { createLDReactProvider } from '@launchdarkly/react-sdk';
const LDReactProvider = createLDReactProvider(import.meta.env.VITE_LD_CLIENT_SIDE_ID, {
  kind: 'user',
  key: 'context-key-123abc',
});
// root.render(<LDReactProvider><Checkout /></LDReactProvider>);
```

```tsx
// checkout.test.tsx — both states, no live LD, NOT jest-launchdarkly-mock (v3-only)
import { render, screen } from '@testing-library/react';
import { Checkout } from './checkout';

// v4-appropriate: mock the single typed hook the seam depends on.
jest.mock('@launchdarkly/react-sdk', () => ({ useBoolVariation: jest.fn() }));
import { useBoolVariation } from '@launchdarkly/react-sdk';

it.each([[true, 'new checkout'], [false, 'legacy checkout']])(
  'flag=%s renders the right checkout',
  (flagOn, expected) => {
    (useBoolVariation as jest.Mock).mockReturnValue(flagOn);
    render(<Checkout />);
    expect(screen.getByText(expected as string)).toBeInTheDocument();
  },
);
```

## Pitfalls

- **Don't scatter the flag read.** Generate exactly one read boundary; callers
  depend on the seam.
- **Don't emit legacy client APIs in the browser/React scaffolds.** Use the v4
  `createClient`/`client.start()` (browser) and `createLDReactProvider` + typed
  hooks (React) — never `initialize()`, `withLDProvider`, or
  `asyncWithLDProvider`.
- **Don't use `jest-launchdarkly-mock` for the React scaffold test.** It targets
  the legacy v3 React SDK; mock the v4 typed hook (or bootstrap the v4 provider)
  instead.
- **Don't put a server SDK key in a browser/React scaffold.** Those targets read
  a client-side ID from env/config.
- **Don't generate a one-branch test.** The test must assert both flag-on and
  flag-off (the off branch is the safe default).
- **Don't hardcode SDK keys.** Generated code reads the key from env/config;
  tests use the offline TestData source with a fake key.
