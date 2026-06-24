---
name: launchdarkly-java-sdk
description: Use when writing or reviewing LaunchDarkly feature-flag code with the server-side Java SDK (com.launchdarkly:launchdarkly-java-server-sdk). Covers adding the dependency, initializing one long-lived shared LDClient and closing it on shutdown, building an LDContext, evaluating boolean and typed variations always with a safe default, offline mode, and deterministic tests with the TestData source. For the conceptual model (contexts, default values, streaming vs polling, lifecycle), see the launchdarkly-fundamentals skill rather than restating it here.
---

# LaunchDarkly Java Server SDK

Concrete guidance for the **server-side** LaunchDarkly Java SDK. This is a
server SDK: it evaluates flags **locally** from a full ruleset and authenticates
with a **secret SDK key**. For what flags, variations, contexts, default values,
and the flag lifecycle *mean*, read the `launchdarkly-fundamentals` skill — this
skill assumes those concepts and focuses on the Java API.

> **Verify against current docs.** The class and method names below reflect the
> 7.x line of `launchdarkly-java-server-sdk`. Confirm the exact dependency
> version and signatures against the current
> [Java SDK reference](https://launchdarkly.com/docs/sdk/server-side/java) and
> [Javadoc](https://launchdarkly.github.io/java-core/lib/sdk/server/) before
> shipping — never invent a method name.

## Add the dependency

**Maven:**

```xml
<dependency>
  <groupId>com.launchdarkly</groupId>
  <artifactId>launchdarkly-java-server-sdk</artifactId>
  <version>7.9.0</version> <!-- check for the latest 7.x release -->
</dependency>
```

**Gradle:**

```groovy
implementation "com.launchdarkly:launchdarkly-java-server-sdk:7.9.0"
```

Imports used throughout:

```java
import com.launchdarkly.sdk.*;          // LDContext, LDValue, ContextKind
import com.launchdarkly.sdk.server.*;   // LDClient, LDConfig
```

## Initialize one shared, long-lived LDClient

`LDClient` is **heavyweight and thread-safe**. Create exactly **one** instance
for the lifetime of the application and share it — never construct an `LDClient`
per request or per evaluation. It opens a streaming connection and caches the
ruleset for local evaluation; building one per request destroys performance and
leaks connections.

Load the SDK key from the environment or your config system — it is a **server
secret**, so never hardcode it or commit it.

```java
public final class FeatureFlags {
  private static final LDClient CLIENT = buildClient();

  private static LDClient buildClient() {
    String sdkKey = System.getenv("LAUNCHDARKLY_SDK_KEY");
    if (sdkKey == null || sdkKey.isBlank()) {
      throw new IllegalStateException("LAUNCHDARKLY_SDK_KEY is not set");
    }
    return new LDClient(sdkKey);
  }

  public static LDClient client() {
    return CLIENT;
  }

  private FeatureFlags() {}
}
```

The constructor begins connecting immediately and blocks until it connects or
`LDConfig.Builder.startWait()` (default 5s) elapses. If you need a custom
configuration, pass an `LDConfig` as the second argument — note the SDK key goes
to the `LDClient` constructor, **not** to `LDConfig.Builder()` (which takes no
arguments):

```java
LDConfig config = new LDConfig.Builder()
    .startWait(java.time.Duration.ofSeconds(5))
    .build();
LDClient client = new LDClient(sdkKey, config);
```

### Close the client on shutdown

`LDClient` implements `Closeable`. Flush events and release the connection by
calling `close()` exactly once when the application stops:

```java
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
  try {
    FeatureFlags.client().close();
  } catch (java.io.IOException e) {
    // log; shutdown is best-effort
  }
}));
```

In a managed container (Spring, etc.) close it from the corresponding lifecycle
hook (e.g. a `@PreDestroy` method) instead of a raw shutdown hook.

## Build an LDContext and evaluate a variation with a default

Build an `LDContext` describing who/what the evaluation is for, then call a
typed `*Variation` method. **The last argument is always the default value**, and
it must be the safe fallback returned when the SDK can't evaluate the flag (not
yet initialized, connection lost, flag missing, invalid context). For a new
feature the safe default is almost always "off" / the current behavior.

```java
LDContext context = LDContext.builder("context-key-123abc")
    .kind("user")                 // defaults to "user" if omitted
    .name("Sandy")
    .set("plan", "enterprise")    // custom attribute used by targeting rules
    .build();

// Boolean flag — false is the SAFE default (feature stays off on any error).
boolean showNewCheckout =
    FeatureFlags.client().boolVariation("new-checkout", context, false);

if (showNewCheckout) {
  // new path
} else {
  // existing path
}
```

Typed variations follow the same `(flagKey, context, default)` shape:

```java
String buttonColor = client.stringVariation("button-color", context, "blue");
int    pageSize    = client.intVariation("page-size", context, 25);
double sampleRate  = client.doubleVariation("sample-rate", context, 0.0);
LDValue config     = client.jsonValueVariation("ui-config", context, LDValue.ofNull());
```

Do **not** call a variation method without a default — there is no defaultless
overload, and supplying an unsafe default (e.g. `true` for an unfinished
feature) means an outage silently turns the feature on for everyone.

## Offline mode and graceful failure

The default value is the SDK's built-in graceful-degradation mechanism: if
LaunchDarkly is unreachable or the SDK key is missing/invalid, every evaluation
simply returns the default you passed, so the application keeps running on the
safe path. Code defensively by choosing safe defaults — you don't need extra
try/catch around `boolVariation`.

To run with no network connection at all (local dev, or an environment that must
never reach LaunchDarkly), enable **offline mode**. Every evaluation then returns
the default value:

```java
LDConfig config = new LDConfig.Builder().offline(true).build();
LDClient client = new LDClient(sdkKey, config);
```

## Deterministic tests with the TestData source

For tests, avoid contacting LaunchDarkly. Use the SDK's `TestData` source from
`com.launchdarkly.sdk.server.integrations.TestData` to control flag values
in-process, and **exercise both the flag-on and flag-off branches**.

```java
import com.launchdarkly.sdk.server.integrations.TestData;

TestData td = TestData.dataSource();
td.update(td.flag("new-checkout").variationForAll(true));   // flag ON for everyone

LDConfig config = new LDConfig.Builder().dataSource(td).build();
LDClient client = new LDClient("fake-key-for-tests", config);

LDContext context = LDContext.builder("test-user").build();

// flag ON branch:
assert client.boolVariation("new-checkout", context, false) == true;

// flip to OFF and assert the other branch:
td.update(td.flag("new-checkout").variationForAll(false));
assert client.boolVariation("new-checkout", context, true) == false;
```

`TestData` flags are updatable at runtime, so you can drive both states within a
single test. Use it for multivariate flags too, e.g.
`td.flag("button-color").variations(LDValue.of("red"), LDValue.of("green")).fallthroughVariation(0)`.

## Pitfalls (Java-specific)

- **One shared `LDClient`, never per request.** It is thread-safe and expensive
  to create; a per-request client cripples performance and leaks connections.
- **Always pass a default, and make it safe.** Every `*Variation` call's last
  argument is the value returned on any error — it must be the conservative
  branch.
- **Keep the SDK key secret.** Load it from env/config; never hardcode or log it.
  Don't log full `LDContext` objects either — they can carry user PII.
- **Don't invent method names.** Verify `LDClient`, `LDContext`, `LDConfig`, and
  `TestData` signatures against the current Java SDK docs.
