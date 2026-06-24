---
name: launchdarkly-testing
description: Use when writing or reviewing tests for LaunchDarkly flag-gated code. Establishes the standard that a flag-gated change is not done until BOTH the flag-on and flag-off branches are tested, and shows how to drive flag values deterministically with no network — the SDK TestData source for Java/JUnit (parameterized over both states) and TypeScript Jest/Vitest (server), and jest-launchdarkly-mock for React components. Tests target the stable seam from the launchdarkly-flag-structure skill; for TestData specifics see the per-SDK skills.
---

# Testing Both Flag States

A flag that is only tested in one state hides bugs in the other — and the
untested branch is usually the one that ships during an incident (the safe
default) or after rollout (the new path). **The standard this plugin enforces: a
flag-gated change is not done until both the flag-on and flag-off branches are
covered by tests.**

Two rules make that practical and reliable:

- **Drive flag values deterministically, with no network.** Use the SDK's
  in-memory TestData source (server SDKs) or a mock provider (React). Never hit
  the live LaunchDarkly service in tests, and never embed a real SDK key.
- **Assert observable behavior, not flag plumbing.** Test through the stable seam
  from the `launchdarkly-flag-structure` skill (which implementation/output you
  get), not whether `variation` was called.

## Java / JUnit — parameterize over both states

Use the Java SDK's `TestData` source (see the `launchdarkly-java-sdk` skill) and
a `@ParameterizedTest` so a single test covers flag-on and flag-off:

```java
import com.launchdarkly.sdk.*;
import com.launchdarkly.sdk.server.*;
import com.launchdarkly.sdk.server.integrations.TestData;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.assertEquals;

class CheckoutFactoryTest {

  @ParameterizedTest
  @ValueSource(booleans = {true, false}) // covers BOTH branches
  void picksImplementationForFlagState(boolean flagOn) throws Exception {
    TestData td = TestData.dataSource();
    td.update(td.flag("new-checkout").booleanFlag().variationForAll(flagOn));

    LDConfig config = new LDConfig.Builder().dataSource(td).build();
    try (LDClient client = new LDClient("test-key", config)) {
      Checkout checkout = new CheckoutFactory(client)
          .forContext(LDContext.builder("test-user").build());

      // observable behavior at the seam, not internal plumbing:
      assertEquals(flagOn ? NewCheckout.class : LegacyCheckout.class, checkout.getClass());
    }
  }
}
```

The `false` case is the safe-default branch — assert it produces the safe
behavior, satisfying the security expectation.

### Java / JUnit — grouped by state with multiple `@Nested` classes

When you prefer to group assertions by flag state rather than parameterize, use
one JUnit 5 `@Nested` inner class per state (the annotation is `@Nested` — there
is no `@NestedTest`). Each nested class sets its own flag value via `TestData`:

```java
import com.launchdarkly.sdk.*;
import com.launchdarkly.sdk.server.*;
import com.launchdarkly.sdk.server.integrations.TestData;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

class CheckoutFactoryTest {

  private Checkout resolve(boolean flagOn) throws Exception {
    TestData td = TestData.dataSource();
    td.update(td.flag("new-checkout").booleanFlag().variationForAll(flagOn));
    try (LDClient client = new LDClient("test-key", new LDConfig.Builder().dataSource(td).build())) {
      return new CheckoutFactory(client).forContext(LDContext.builder("test-user").build());
    }
  }

  @Nested
  class WhenFlagOn {
    @Test
    void usesNewCheckout() throws Exception {
      assertEquals(NewCheckout.class, resolve(true).getClass());
    }
  }

  @Nested
  class WhenFlagOff { // safe-default branch
    @Test
    void usesLegacyCheckout() throws Exception {
      assertEquals(LegacyCheckout.class, resolve(false).getClass());
    }
  }
}
```

Both `@Nested` classes are present, so both branches are covered — the on-state
and the off (safe-default) state each get their own clearly named group.

## TypeScript Jest/Vitest (server) — both states

Use the Node SDK's `TestData` source (see the `launchdarkly-typescript-node`
skill), wired via `updateProcessor: td.getFactory()`, and table-driven cases:

```typescript
import { init } from '@launchdarkly/node-server-sdk';
import { TestData } from '@launchdarkly/node-server-sdk/integrations';
import { resolveCheckout, NewCheckout, LegacyCheckout } from './checkout-factory';

describe('resolveCheckout', () => {
  it.each([
    [true, NewCheckout],     // flag ON
    [false, LegacyCheckout], // flag OFF — safe default
  ])('flag=%s resolves the right implementation', async (flagOn, expected) => {
    const td = new TestData();
    td.update(td.flag('new-checkout').booleanFlag().variationForAll(flagOn));

    const client = init('test-key', { updateProcessor: td.getFactory() });
    await client.waitForInitialization({ timeout: 10 });

    const checkout = await resolveCheckout(client, { kind: 'user', key: 'test-user' });
    expect(checkout).toBeInstanceOf(expected);

    await client.close();
  });
});
```

### TypeScript Jest/Vitest — grouped by state with multiple `describe` blocks

To group by flag state instead of a table, use one `describe` block per state,
each configuring its own `TestData` value:

```typescript
import { init } from '@launchdarkly/node-server-sdk';
import { TestData } from '@launchdarkly/node-server-sdk/integrations';
import { resolveCheckout, NewCheckout, LegacyCheckout } from './checkout-factory';

describe('resolveCheckout', () => {
  describe('when the flag is on', () => {
    it('uses the new checkout', async () => {
      const td = new TestData();
      td.update(td.flag('new-checkout').booleanFlag().variationForAll(true));
      const client = init('test-key', { updateProcessor: td.getFactory() });
      await client.waitForInitialization({ timeout: 10 });

      const checkout = await resolveCheckout(client, { kind: 'user', key: 'u' });
      expect(checkout).toBeInstanceOf(NewCheckout);
      await client.close();
    });
  });

  describe('when the flag is off', () => { // safe-default branch
    it('uses the legacy checkout', async () => {
      const td = new TestData();
      td.update(td.flag('new-checkout').booleanFlag().variationForAll(false));
      const client = init('test-key', { updateProcessor: td.getFactory() });
      await client.waitForInitialization({ timeout: 10 });

      const checkout = await resolveCheckout(client, { kind: 'user', key: 'u' });
      expect(checkout).toBeInstanceOf(LegacyCheckout);
      await client.close();
    });
  });
});
```

Both `describe` blocks are present, so both the flag-on and flag-off (safe
default) branches are exercised — just organized by state instead of a table.

## React components — both states with jest-launchdarkly-mock

For React components that read flags via `useFlags`/`useLDClient`, use the
official `jest-launchdarkly-mock` package. Add it to your Jest setup so the React
SDK is auto-mocked, then drive flag values per test with `mockFlags` (keys may be
camelCased) and reset between tests with `resetLDMocks`:

```tsx
import { mockFlags, resetLDMocks } from 'jest-launchdarkly-mock';
import { render, screen } from '@testing-library/react';
import { Checkout } from './Checkout';

beforeEach(() => {
  resetLDMocks(); // clean slate each test
});

test('flag ON renders the new checkout', () => {
  mockFlags({ newCheckout: true });
  render(<Checkout />);
  expect(screen.getByTestId('new-checkout')).toBeInTheDocument();
});

test('flag OFF renders the legacy checkout (safe default)', () => {
  mockFlags({ newCheckout: false });
  render(<Checkout />);
  expect(screen.getByTestId('legacy-checkout')).toBeInTheDocument();
});
```

`jest-launchdarkly-mock` also exposes `ldClientMock` (a jest mock of the client)
when you need to assert `identify`/`track` calls — but prefer asserting rendered
output over client interactions.

## Multivariate flags

For a flag with more than two variations, two tests aren't enough — **cover each
meaningful variation**. Drive each value through the same TestData/mockFlags
mechanism (e.g. `td.flag(key).variations(LDValue.of("red"), LDValue.of("green"), LDValue.of("blue")).variationForAll(n)`,
or `mockFlags({ buttonColor: 'green' })`) and assert the behavior for every
branch a user can actually receive.

## The standard

- A flag-gated change is **not complete** until tests cover **every branch** the
  flag can select — at minimum flag-on and flag-off, and every meaningful
  variation for multivariate flags.
- Tests use the **TestData source / mock provider**, never live LaunchDarkly, and
  never a real SDK key.
- The **off / safe-default branch** is explicitly asserted to produce the safe
  behavior.

## Pitfalls

- **Don't test only the flag-on branch.** The off branch ships during outages and
  before rollout — it must be covered.
- **Don't hit the live LaunchDarkly service in tests.** Use TestData (server) or
  jest-launchdarkly-mock (React); no real SDK keys in tests.
- **Don't assert on internal flag plumbing.** Assert observable behavior through
  the stable seam, not that `variation` was invoked.
