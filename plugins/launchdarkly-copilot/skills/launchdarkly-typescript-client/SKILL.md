---
name: launchdarkly-typescript-client
description: Use when writing or reviewing LaunchDarkly feature-flag code that runs in the browser — the client-side JavaScript SDK (@launchdarkly/js-client-sdk) and the React SDK (@launchdarkly/react-sdk) in TypeScript. Covers initializing with a client-side ID (never a server SDK key) via createClient + client.start(), the identify context model, bootstrapping to avoid flash-of-default, streaming updates, the createLDReactProvider provider and the typed hooks (useBoolVariation, useInitializationStatus, useLDClient), plus SSR/hydration considerations. For the conceptual model (contexts, default values, streaming vs polling, lifecycle), see the launchdarkly-fundamentals skill rather than restating it here.
---

# LaunchDarkly Client-Side (Browser JS + React) SDK

Concrete guidance for the **client-side** LaunchDarkly SDKs that run in the
browser: the JavaScript SDK and the React wrapper, in TypeScript. These are
client-side SDKs — they **delegate evaluation** to LaunchDarkly for one context
and authenticate with a **client-side ID**, not a secret SDK key. For what flags,
contexts, and default values *mean*, read the `launchdarkly-fundamentals` skill.

The primary path is the scoped v4 packages: **`@launchdarkly/js-client-sdk`**
(browser) and **`@launchdarkly/react-sdk`** (React). The older unscoped packages
are still published and covered under [Legacy v3](#legacy-v3-still-published-not-deprecated)
at the bottom, but new code should use v4.

> **Verify against current docs.** The API below reflects the v4 scoped
> `@launchdarkly/js-client-sdk` and `@launchdarkly/react-sdk` packages. Confirm
> signatures against the current
> [JavaScript SDK reference](https://launchdarkly.com/docs/sdk/client-side/javascript)
> and [React Web SDK reference](https://launchdarkly.com/docs/sdk/client-side/react/react-web)
> before shipping — never invent a method name.

## Security: client-side ID only

Browser code is fully visible to end users. Two rules are non-negotiable:

- **Use the client-side ID, never a server SDK key.** A server SDK key grants
  read access to your entire ruleset; embedding it in a frontend bundle leaks
  every flag rule and other contexts' data. The browser and React SDKs take the
  **client-side ID** (designed to be public). Each flag must have "Make this flag
  available to client-side SDKs" enabled.
- **Client-side flag values are visible to users.** Never gate secret-dependent
  or security-critical logic purely on a client-side flag — a user can read the
  value and the gated code. Enforce anything sensitive on the server.

## Browser JavaScript SDK

Install:

```bash
npm install @launchdarkly/js-client-sdk
```

In v4, initialization is a **two-step** process: `createClient` builds the client
(so you can register event listeners first), then `client.start()` begins
connecting. A client-side SDK is configured for one context at a time; evaluations
use that context, so the typed variation methods take **no context argument**.

```typescript
import { createClient, type LDClient, type LDContext } from '@launchdarkly/js-client-sdk';

const context: LDContext = { kind: 'user', key: 'context-key-123abc', name: 'Sandy' };

// First arg is the CLIENT-SIDE ID, never a server SDK key.
const client: LDClient = createClient('YOUR_CLIENT_SIDE_ID', context);

client.start();
```

### Waiting for initialization (never rejects)

`client.start()` and `client.waitForInitialization({ timeout })` both **resolve
with a status object** — they never reject on failure. Inspect `result.status`
(`'complete' | 'failed' | 'timeout'`) instead of wrapping the call in a
`try/catch`:

```typescript
const result = await client.waitForInitialization({ timeout: 5 });

if (result.status === 'complete') {
  // Real flag values are available.
} else if (result.status === 'timeout') {
  // Initialization did not finish in time — fall back to defaults.
} else if (result.status === 'failed') {
  // result.error holds the failure reason — fall back to defaults.
}

// No context arg — the context was set at createClient. Last arg is the SAFE default.
const showNewCheckout: boolean = client.boolVariation('new-checkout', false);
```

The typed variation methods return the type they name and each take a safe
default as the last argument: `boolVariation`, `stringVariation`,
`numberVariation`, and `jsonVariation`. None of them take a context argument.

Change the context when the user logs in or their attributes change:

```typescript
await client.identify({ kind: 'user', key: 'logged-in-user-key', name: 'Sandy' });
```

Subscribe to **streaming updates** so the UI reacts when a flag changes
server-side without a reload:

```typescript
client.on('change', () => {
  // re-evaluate and re-render with the new value(s)
});
```

### Bootstrapping (avoid flash-of-default)

Without bootstrapping, the SDK makes a network request on init, so for a brief
moment the typed variation methods return your defaults — a "flash of default"
(e.g. the old UI flickers before the flagged one appears). **Bootstrapping**
seeds initial flag values that are available immediately, before any network
round trip. Pass them as an option to `createClient`:

```typescript
const client = createClient('YOUR_CLIENT_SIDE_ID', context, {
  bootstrap: serverProvidedFlagValues, // flag values evaluated on the server
});
```

Pass values your server already evaluated (see SSR below) as a plain
key-value object, e.g. `{ 'new-checkout': true }`. A bootstrapped client has real
values available on its first evaluation, so there is no flash-of-default.

## React SDK

Install:

```bash
npm install @launchdarkly/react-sdk
```

The React SDK wraps the JS SDK and exposes flags via React context. Create the
provider with **`createLDReactProvider`** at the app entry point, **before**
rendering, so flags and the client are ready at the start of the app lifecycle:

```tsx
import { createLDReactProvider } from '@launchdarkly/react-sdk';

const LDReactProvider = createLDReactProvider('YOUR_CLIENT_SIDE_ID', {
  kind: 'user',
  key: 'context-key-123abc',
});

root.render(
  <LDReactProvider>
    <App />
  </LDReactProvider>,
);
```

`createLDReactProvider(clientSideID, context, options?)` also accepts a top-level
`bootstrap` option — a plain key-value object such as `{ 'new-checkout': true }` —
to avoid a flash-of-default on first render (see SSR below).

### Reading flags with the typed hooks

Use the **typed variation hooks** — `useBoolVariation`, `useStringVariation`,
`useNumberVariation`, `useJsonVariation` (plus `*VariationDetail` variants) — each
of which takes a flag key and a safe default. Use `useInitializationStatus` to
know when real values are ready, and `useLDClient` for the underlying JS client
(for `identify`, `track`, event listeners):

```tsx
import {
  useBoolVariation,
  useInitializationStatus,
  useLDClient,
} from '@launchdarkly/react-sdk';

function Checkout() {
  const status = useInitializationStatus();
  const ldClient = useLDClient();
  const newCheckout = useBoolVariation('new-checkout', false);

  // Until initialization is complete, variations fall back to their defaults —
  // handle that loading state rather than assuming a real value.
  if (status.status !== 'complete') {
    return <Spinner />;
  }

  return newCheckout ? <NewCheckout /> : <LegacyCheckout />;
}
```

## SSR / hydration considerations

With server-side rendering (e.g. Next.js), the server renders HTML before the
browser SDK has initialized. If the server renders with default flag values and
the client then loads real values, React's hydration sees a mismatch (and the
user sees a flash-of-default). Avoid it by **bootstrapping with server-evaluated
values**:

1. On the server, evaluate the flags for the request's context using a
   **server-side SDK** (e.g. `@launchdarkly/node-server-sdk`) — never the
   client-side ID for evaluation logic.
2. Serialize those flag values into the page as a plain key-value object.
3. Pass them as the `bootstrap` option to `createClient` or as the top-level
   `bootstrap` option on `createLDReactProvider` so the client's first render
   matches the server's HTML — no hydration mismatch, no flash-of-default.

## Pitfalls (client-side-specific)

- **Client-side ID only.** Never embed a server SDK key in a browser/React
  bundle; never gate secret-dependent logic purely on a client-side flag (values
  are visible to users).
- **Don't read flags before init.** Handle the loading/not-ready state
  (`useInitializationStatus` not `'complete'`, or a non-`'complete'`
  `waitForInitialization` status); pre-init evaluations return defaults, not real
  values.
- **Don't treat init as throwing.** `start()` / `waitForInitialization` resolve
  with a status object and never reject — branch on `result.status`, don't wrap
  them in `try/catch` expecting a rejection.
- **Don't ignore SSR hydration.** Bootstrap with server-evaluated values so the
  server HTML and client's first render agree.
- **Keep examples typed and idiomatic.** TypeScript with function components and
  hooks; pass a safe default to every evaluation.

## Legacy v3 (still published, not deprecated)

The unscoped v3 packages — `launchdarkly-js-client-sdk` (browser) and
`launchdarkly-react-client-sdk` (React) — are **still published and not
npm-deprecated**, so existing code keeps working. New code should use the v4
scoped packages above; this section exists to read and maintain v3 code. See the
[JavaScript 3.x → 4.0 migration guide](https://launchdarkly.com/docs/sdk/client-side/javascript/migration-3-to-4)
to upgrade.

**Browser (v3):** initialize with `initialize()` (removed in v4 in favour of
`createClient` + `start`). In v3, `waitForInitialization()` **rejects** on
failure — the opposite of the v4 status-object model — so it must be wrapped in a
`try/catch`. Evaluations use the untyped `variation(key, default)` method.

```typescript
import { initialize, type LDClient, type LDContext } from 'launchdarkly-js-client-sdk';

const context: LDContext = { kind: 'user', key: 'context-key-123abc', name: 'Sandy' };
const client: LDClient = initialize('YOUR_CLIENT_SIDE_ID', context);

try {
  await client.waitForInitialization(); // v3: REJECTS on failure
} catch {
  // fall back to defaults
}

const showNewCheckout = client.variation('new-checkout', false); // untyped
```

**React (v3):** wrap the app with one of two provider factories from
`launchdarkly-react-client-sdk`, both **removed in v4**:

- `withLDProvider` (HOC) — initializes the client at mount; the app renders first
  and flags arrive after mount.
- `asyncWithLDProvider` — `await` it during startup; it delays rendering until
  initialization completes.

```tsx
import { asyncWithLDProvider } from 'launchdarkly-react-client-sdk';

const LDProvider = await asyncWithLDProvider({
  clientSideID: 'YOUR_CLIENT_SIDE_ID',
  context: { kind: 'user', key: 'context-key-123abc' },
});

root.render(
  <LDProvider>
    <App />
  </LDProvider>,
);
```

Read flags with `useFlags` — **deprecated in v4** in favour of the typed
variation hooks. It returns all flags as **camelCased** props (a flag keyed
`new-checkout` becomes `newCheckout`); `useLDClient` returns the underlying JS
client:

```tsx
import { useFlags, useLDClient } from 'launchdarkly-react-client-sdk';

function Checkout() {
  const { newCheckout } = useFlags(); // deprecated in v4
  const ldClient = useLDClient();

  if (!ldClient) {
    return <Spinner />;
  }

  return newCheckout ? <NewCheckout /> : <LegacyCheckout />;
}
```
