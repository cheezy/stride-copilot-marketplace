---
name: launchdarkly-typescript-client
description: Use when writing or reviewing LaunchDarkly feature-flag code that runs in the browser — the client-side JavaScript SDK (launchdarkly-js-client-sdk) and the React SDK (launchdarkly-react-client-sdk) in TypeScript. Covers initializing with a client-side ID (never a server SDK key), the identify context model, bootstrapping to avoid flash-of-default, streaming updates, the React LDProvider (withLDProvider and asyncWithLDProvider) and the useFlags / useLDClient hooks, plus SSR/hydration considerations. For the conceptual model (contexts, default values, streaming vs polling, lifecycle), see the launchdarkly-fundamentals skill rather than restating it here.
---

# LaunchDarkly Client-Side (Browser JS + React) SDK

Concrete guidance for the **client-side** LaunchDarkly SDKs that run in the
browser: the JavaScript SDK and the React wrapper, in TypeScript. These are
client-side SDKs — they **delegate evaluation** to LaunchDarkly for one context
and authenticate with a **client-side ID**, not a secret SDK key. For what flags,
contexts, and default values *mean*, read the `launchdarkly-fundamentals` skill.

> **Verify against current docs.** The API below reflects the established
> `launchdarkly-js-client-sdk` and `launchdarkly-react-client-sdk` packages.
> Confirm signatures against the current
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
npm install launchdarkly-js-client-sdk
```

Initialize with the **client-side ID** and the initial context. A client-side
SDK is configured for one context at a time; evaluations use that context, so
`variation` takes **no context argument**. Wait for readiness before relying on
real values.

```typescript
import { initialize, LDClient, LDContext } from 'launchdarkly-js-client-sdk';

const context: LDContext = { kind: 'user', key: 'context-key-123abc', name: 'Sandy' };

// First arg is the CLIENT-SIDE ID, never a server SDK key.
const client: LDClient = initialize('YOUR_CLIENT_SIDE_ID', context);

await client.waitForInitialization(); // or: client.on('ready', () => { ... })

// No context arg — the context was set at init. Last arg is the SAFE default.
const showNewCheckout: boolean = client.variation('new-checkout', false);
```

Change the context when the user logs in or their attributes change:

```typescript
await client.identify({ kind: 'user', key: 'logged-in-user-key', name: 'Sandy' });
```

Subscribe to **streaming updates** so the UI reacts when a flag changes
server-side without a reload:

```typescript
client.on('change:new-checkout', (value: boolean) => {
  // re-render with the new value
});
```

### Bootstrapping (avoid flash-of-default)

Without bootstrapping, the SDK makes a network request on init, so for a brief
moment `variation` returns your defaults — a "flash of default" (e.g. the old UI
flickers before the flagged one appears). **Bootstrapping** seeds initial flag
values that are available immediately, before any network round trip:

```typescript
const client = initialize('YOUR_CLIENT_SIDE_ID', context, {
  bootstrap: serverProvidedFlagValues, // flag values evaluated on the server
});
```

Pass values your server already evaluated (see SSR below). A bootstrapped client
emits `ready` immediately. You can also pass `bootstrap: 'localStorage'` to reuse
the last-known values across page loads.

## React SDK

Install:

```bash
npm install launchdarkly-react-client-sdk
```

The React SDK wraps the JS SDK and exposes flags via React context. Wrap the app
in an `LDProvider`. There are two ways to create it:

**`withLDProvider` (HOC)** — initializes the client at mount, so the app renders
first and flags arrive after mount. Use when you want to render immediately and
handle the not-yet-ready state in components:

```tsx
import { withLDProvider } from 'launchdarkly-react-client-sdk';

function App() {
  return <Routes />;
}

export default withLDProvider({
  clientSideID: 'YOUR_CLIENT_SIDE_ID',
  context: { kind: 'user', key: 'context-key-123abc' },
})(App);
```

**`asyncWithLDProvider`** — `await` it during startup; it delays rendering until
initialization completes, which avoids a flash-of-default at the cost of a
slightly later first paint:

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

### Reading flags with useFlags / useLDClient

`useFlags` returns all flags as **camelCased** props (a flag keyed
`new-checkout` becomes `newCheckout`). `useLDClient` returns the underlying JS
client (for `identify`, `track`, event listeners):

```tsx
import { useFlags, useLDClient } from 'launchdarkly-react-client-sdk';

function Checkout() {
  const { newCheckout } = useFlags();
  const ldClient = useLDClient();

  // Until the provider has initialized, flags fall back to their defaults —
  // handle that loading state rather than assuming a real value.
  if (!ldClient) {
    return <Spinner />;
  }

  return newCheckout ? <NewCheckout /> : <LegacyCheckout />;
}
```

> Newer React SDK majors add typed hooks (`useBoolVariation`, etc.) and deprecate
> `useFlags`; check the version you depend on. The `useFlags` / `useLDClient`
> pattern above is the established API for `launchdarkly-react-client-sdk`.

## SSR / hydration considerations

With server-side rendering (e.g. Next.js), the server renders HTML before the
browser SDK has initialized. If the server renders with default flag values and
the client then loads real values, React's hydration sees a mismatch (and the
user sees a flash-of-default). Avoid it by **bootstrapping with server-evaluated
values**:

1. On the server, evaluate the flags for the request's context using a
   **server-side SDK** (e.g. `@launchdarkly/node-server-sdk`) — never the
   client-side ID for evaluation logic.
2. Serialize those flag values into the page.
3. Pass them as the `bootstrap` option to the browser/React provider so the
   client's first render matches the server's HTML — no hydration mismatch, no
   flash-of-default.

## Pitfalls (client-side-specific)

- **Client-side ID only.** Never embed a server SDK key in a browser/React
  bundle; never gate secret-dependent logic purely on a client-side flag (values
  are visible to users).
- **Don't read flags before init.** Handle the loading/not-ready state
  (`useLDClient` null, `waitForInitialization`, or `asyncWithLDProvider`);
  pre-init evaluations return defaults, not real values.
- **Don't ignore SSR hydration.** Bootstrap with server-evaluated values so the
  server HTML and client's first render agree.
- **Keep examples typed and idiomatic.** TypeScript with function components and
  hooks; pass a safe default to every evaluation.
