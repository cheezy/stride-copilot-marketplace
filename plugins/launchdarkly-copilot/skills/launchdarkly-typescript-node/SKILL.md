---
name: launchdarkly-typescript-node
description: Use when writing or reviewing LaunchDarkly feature-flag code with the server-side Node.js SDK (@launchdarkly/node-server-sdk) in TypeScript. Covers installing the SDK, initializing the client and awaiting waitForInitialization before serving traffic, building a typed LDContext, evaluating variations (typed) always with a safe default, flushing and closing on shutdown, and deterministic Jest/Vitest tests with the TestData source. For the conceptual model (contexts, default values, streaming vs polling, lifecycle), see the launchdarkly-fundamentals skill rather than restating it here.
---

# LaunchDarkly TypeScript Node Server SDK

Concrete guidance for the **server-side** LaunchDarkly Node.js SDK, in
TypeScript. This is a server SDK: it evaluates flags **locally** from a full
ruleset and authenticates with a **secret SDK key** that must never reach the
browser bundle. For what flags, variations, contexts, and default values *mean*,
read the `launchdarkly-fundamentals` skill — this skill assumes those concepts
and focuses on the Node/TypeScript API.

> **Verify against current docs.** The API below reflects the modern
> `@launchdarkly/node-server-sdk` package (the 8.x/9.x line; the legacy
> `launchdarkly-node-server-sdk` package has a different TestData wiring).
> Confirm signatures against the current
> [Node.js SDK reference](https://launchdarkly.com/docs/sdk/server-side/node-js)
> before shipping — never invent a method name.

## Install

```bash
npm install @launchdarkly/node-server-sdk
```

## Initialize the client and wait for initialization

Create **one** long-lived client for the process and share it — never call
`init` per request. The SDK opens a streaming connection and evaluates locally;
a per-request client cripples performance.

`init` returns immediately, but evaluations before the client is ready return
your default value, not real flag values. **Await `waitForInitialization` before
serving traffic.** The modern SDK has no built-in timeout, so always pass one (in
seconds) and handle the failure path.

Load the SDK key from the environment — it is a **server secret**; never hardcode
it or expose it to client/browser code.

```typescript
import { init, LDClient } from '@launchdarkly/node-server-sdk';

const sdkKey = process.env.LAUNCHDARKLY_SDK_KEY;
if (!sdkKey) {
  throw new Error('LAUNCHDARKLY_SDK_KEY is not set');
}

export const ldClient: LDClient = init(sdkKey);

export async function initLaunchDarkly(): Promise<void> {
  try {
    await ldClient.waitForInitialization({ timeout: 10 });
    // client is ready — safe to evaluate flags and serve traffic
  } catch (err) {
    // initialization failed or timed out; evaluations will return defaults
    console.error('LaunchDarkly failed to initialize', err);
  }
}
```

Call `initLaunchDarkly()` during startup and `await` it before the server begins
accepting requests, so no evaluation runs against an uninitialized client.

## Build a context and evaluate a variation with a default

An evaluation context is a plain typed object. `client.variation` is
asynchronous and returns a `Promise`; **the last argument is the default value**,
returned whenever the SDK can't evaluate (not initialized, connection lost, flag
missing). Make the default the safe branch — for a new feature, that's "off".

The Node SDK exposes a single `variation` method for all flag types (there are no
`boolVariation`-style typed methods). Annotate the result and pass a default of
the matching type so your TypeScript stays typed end to end.

```typescript
import { LDContext } from '@launchdarkly/node-server-sdk';
import { ldClient } from './launchdarkly';

const context: LDContext = {
  kind: 'user',
  key: 'context-key-123abc',
  name: 'Sandy',
  plan: 'enterprise', // custom attribute used by targeting rules
};

// Boolean flag — false is the SAFE default (feature stays off on any error).
const showNewCheckout: boolean = await ldClient.variation(
  'new-checkout',
  context,
  false,
);

if (showNewCheckout) {
  // new path
} else {
  // existing path
}
```

Typed evaluations for other flag types follow the same
`variation(flagKey, context, default)` shape — the default's type drives the
result type:

```typescript
const buttonColor: string = await ldClient.variation('button-color', context, 'blue');
const pageSize: number = await ldClient.variation('page-size', context, 25);
```

Never call `variation` without a default, and never default to an unsafe value
(e.g. `true` for an unfinished feature) — the default is exactly what ships
during an outage. Use `variationDetail` when you also need the evaluation reason.

## Flush and close on shutdown

`close` releases the connection and flushes pending analytics events. If the
process is about to exit, `flush` first so no events are lost:

```typescript
process.on('SIGTERM', async () => {
  await ldClient.flush();
  await ldClient.close();
  process.exit(0);
});
```

## Deterministic tests with the TestData source

For Jest/Vitest tests, avoid contacting LaunchDarkly. Use the `TestData` source
from `@launchdarkly/node-server-sdk/integrations` to control flag values
in-process, wire it in via the `updateProcessor` option using
`td.getFactory()`, and **exercise both the flag-on and flag-off branches**.

```typescript
import { init } from '@launchdarkly/node-server-sdk';
import { TestData } from '@launchdarkly/node-server-sdk/integrations';

const td = new TestData();
td.update(td.flag('new-checkout').booleanFlag().variationForAll(true)); // ON for everyone

const client = init('fake-key-for-tests', { updateProcessor: td.getFactory() });
await client.waitForInitialization({ timeout: 10 });

const context = { kind: 'user', key: 'test-user' };

// flag ON branch:
expect(await client.variation('new-checkout', context, false)).toBe(true);

// flip to OFF and assert the other branch:
td.update(td.flag('new-checkout').variationForAll(false));
expect(await client.variation('new-checkout', context, true)).toBe(false);

await client.close();
```

`TestData` flags update at runtime, so a single test can drive both states. For
multivariate flags, set explicit variations, e.g.
`td.flag('button-color').variations('red', 'green').fallthroughVariation(0)`.

## Pitfalls (Node/TypeScript-specific)

- **Await `waitForInitialization` before evaluating.** Evaluations against an
  uninitialized client silently return defaults, not real flag values.
- **One shared client, never per request.** `init` opens a streaming connection;
  a per-request client destroys performance.
- **Always pass a default, and make it safe.** `variation`'s last argument is what
  ships on any error — it must be the conservative branch.
- **Keep examples typed.** Annotate `LDContext` and evaluation results; don't fall
  back to untyped JavaScript.
- **Keep the SDK key server-side.** Load from `process.env`; never bundle it into
  browser code, and don't log full contexts (they can carry PII).
