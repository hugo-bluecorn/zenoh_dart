# Phase 18: z_advanced_pub + z_advanced_sub (Advanced Pub/Sub)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–17 — all completed
- Full pub/sub, SHM, discovery, query/reply, channels, pull, querier, liveliness,
  ping/pong, throughput, serialization, storage

## This Phase's Goal

Implement advanced publisher/subscriber with cache, history recovery, publisher
detection, and sample miss detection. These are the most complex zenoh entities
with the most configuration options.

**Reference examples**:
- `extern/zenoh-c/examples/z_advanced_pub.c` — publisher with cache and heartbeat
- `extern/zenoh-c/examples/z_advanced_sub.c` — subscriber with history recovery and miss detection

### Advanced features

**Advanced Publisher**:
- **Cache**: Stores last N samples so late subscribers can retrieve history
- **Publisher detection**: Allows subscribers to detect this publisher
- **Sample miss detection**: Heartbeat mode (PERIODIC) so subscribers can detect gaps

**Advanced Subscriber**:
- **History**: Retrieve cached samples from publishers on connect
- **Recovery**: Recover missed samples
- **Subscriber detection**: Announced to publishers
- **Miss listener**: Callback when sample gaps are detected

### Configuration requirements

Advanced features require timestamp configuration on the session:
```c
zc_config_insert_json5(z_loan(config), Z_CONFIG_ADD_TIMESTAMP_KEY, "true");
```

## C Shim Functions to Add

### Advanced Publisher

```c
// Declare an advanced publisher with options
FFI_PLUGIN_EXPORT int zd_declare_advanced_publisher(
    const z_loaned_session_t* session,
    ze_owned_advanced_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    bool enable_cache,
    size_t cache_max_samples,
    bool publisher_detection,
    bool sample_miss_detection,
    int heartbeat_mode);    // 0 = none, 1 = periodic

// Publish through advanced publisher
FFI_PLUGIN_EXPORT int zd_advanced_publisher_put(
    const ze_loaned_advanced_publisher_t* publisher,
    z_owned_bytes_t* payload);

// Loan the advanced publisher
FFI_PLUGIN_EXPORT const ze_loaned_advanced_publisher_t* zd_advanced_publisher_loan(
    const ze_owned_advanced_publisher_t* publisher);

// Drop the advanced publisher
FFI_PLUGIN_EXPORT void zd_advanced_publisher_drop(
    ze_owned_advanced_publisher_t* publisher);
```

### Advanced Subscriber

```c
// Declare an advanced subscriber with options
FFI_PLUGIN_EXPORT int zd_declare_advanced_subscriber(
    const z_loaned_session_t* session,
    ze_owned_advanced_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port,
    bool history,
    bool history_detect_late_publishers,
    bool recovery,
    bool subscriber_detection);

// Declare a background sample miss listener on advanced subscriber
// Miss events posted to dart_port: [source_zid, nb_missed]
FFI_PLUGIN_EXPORT int zd_advanced_subscriber_declare_background_sample_miss_listener(
    const ze_loaned_advanced_subscriber_t* subscriber,
    int64_t dart_port);

// Loan the advanced subscriber
FFI_PLUGIN_EXPORT const ze_loaned_advanced_subscriber_t* zd_advanced_subscriber_loan(
    const ze_owned_advanced_subscriber_t* subscriber);

// Drop the advanced subscriber
FFI_PLUGIN_EXPORT void zd_advanced_subscriber_drop(
    ze_owned_advanced_subscriber_t* subscriber);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_advanced_publisher` | `ze_declare_advanced_publisher`, `ze_advanced_publisher_options_default`, `ze_advanced_publisher_cache_options_default`, `ze_advanced_publisher_sample_miss_detection_options_default` |
| `zd_advanced_publisher_put` | `ze_advanced_publisher_put`, `ze_advanced_publisher_put_options_default` |
| `zd_advanced_publisher_loan` | `ze_advanced_publisher_loan` (macro) |
| `zd_advanced_publisher_drop` | `ze_advanced_publisher_drop` (macro) |
| `zd_declare_advanced_subscriber` | `ze_declare_advanced_subscriber`, `ze_advanced_subscriber_options_default`, `ze_advanced_subscriber_history_options_default`, `ze_advanced_subscriber_recovery_options_default` |
| `zd_advanced_subscriber_declare_background_sample_miss_listener` | `ze_advanced_subscriber_declare_background_sample_miss_listener`, `ze_closure_miss` |
| `zd_advanced_subscriber_loan` | `ze_advanced_subscriber_loan` (macro) |
| `zd_advanced_subscriber_drop` | `ze_advanced_subscriber_drop` (macro) |

Also uses `zc_config_insert_json5` (from Phase 0) for timestamp configuration.

## Dart API Surface

### New file: `packages/zenoh/lib/src/advanced_publisher.dart`

```dart
/// An advanced publisher with caching, detection, and miss detection.
class AdvancedPublisher {
  /// Publish a string value.
  void put(String value);

  /// Publish raw bytes.
  void putBytes(ZBytes payload);

  /// Close the advanced publisher.
  void close();
}

/// Options for configuring an advanced publisher.
class AdvancedPublisherOptions {
  /// Enable sample cache with max number of samples.
  final int? cacheMaxSamples;

  /// Enable publisher detection (subscribers can detect this publisher).
  final bool publisherDetection;

  /// Enable sample miss detection with periodic heartbeat.
  final bool sampleMissDetection;

  const AdvancedPublisherOptions({
    this.cacheMaxSamples,
    this.publisherDetection = false,
    this.sampleMissDetection = false,
  });
}
```

### New file: `packages/zenoh/lib/src/advanced_subscriber.dart`

```dart
/// An advanced subscriber with history recovery and miss detection.
class AdvancedSubscriber {
  /// Stream of received samples (includes recovered history).
  Stream<Sample> get stream;

  /// Stream of miss events (sample gaps detected).
  Stream<MissEvent>? get missEvents;

  /// Close the advanced subscriber.
  void close();
}

/// Information about missed samples.
class MissEvent {
  /// Zenoh ID of the source that had gaps.
  final ZenohId sourceId;

  /// Number of missed samples.
  final int count;
}

/// Options for configuring an advanced subscriber.
class AdvancedSubscriberOptions {
  /// Enable history retrieval on connect.
  final bool history;

  /// Detect publishers that start after this subscriber.
  final bool detectLatePublishers;

  /// Enable sample recovery.
  final bool recovery;

  /// Enable subscriber detection (publishers can detect this subscriber).
  final bool subscriberDetection;

  /// Enable miss detection listener.
  final bool enableMissListener;

  const AdvancedSubscriberOptions({
    this.history = false,
    this.detectLatePublishers = false,
    this.recovery = false,
    this.subscriberDetection = false,
    this.enableMissListener = false,
  });
}
```

### Modify `packages/zenoh/lib/src/session.dart`

```dart
class Session {
  /// Declare an advanced publisher.
  AdvancedPublisher declareAdvancedPublisher(
    String keyExpr, {
    AdvancedPublisherOptions options = const AdvancedPublisherOptions(),
  });

  /// Declare an advanced subscriber.
  AdvancedSubscriber declareAdvancedSubscriber(
    String keyExpr, {
    AdvancedSubscriberOptions options = const AdvancedSubscriberOptions(),
  });
}
```

### Modify `packages/zenoh/lib/zenoh.dart`

Add exports for `AdvancedPublisher`, `AdvancedSubscriber`, options, `MissEvent`.

## CLI Examples to Create

### `packages/zenoh/bin/z_advanced_pub.dart`

Mirrors `extern/zenoh-c/examples/z_advanced_pub.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_advanced_pub.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-advanced-pub')
    -p, --payload <VALUE>  (default: 'Advanced Pub from Dart!')
    --cache <MAX_SAMPLES>  (default: 1)
    --history              (flag: enable publisher detection)
    --no-heartbeat         (flag: disable sample miss detection)
```

Behavior:
1. Create config with timestamp enabled (`Z_CONFIG_ADD_TIMESTAMP_KEY: "true"`)
2. Open session
3. Declare advanced publisher with cache, detection, heartbeat
4. Loop: publish `"[<idx>] <value>"` every second
5. Run until SIGINT
6. Close

### `packages/zenoh/bin/z_advanced_sub.dart`

Mirrors `extern/zenoh-c/examples/z_advanced_sub.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_advanced_sub.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-advanced-pub')
    --history              (flag: enable history retrieval)
    --recovery             (flag: enable sample recovery)
    --no-detection         (flag: disable subscriber detection)
```

Behavior:
1. Open session
2. Declare advanced subscriber with history/recovery/detection
3. Optionally declare miss listener
4. Print received samples and miss events
5. Run until SIGINT
6. Close

### Usage scenario

```bash
# Terminal 1: Start advanced publisher (publishes with cache)
fvm dart run -C packages/zenoh bin/z_advanced_pub.dart --cache 10

# Wait a few seconds (publisher caches samples)

# Terminal 2: Start advanced subscriber with history
fvm dart run -C packages/zenoh bin/z_advanced_sub.dart --history --recovery
# → Should receive cached samples from publisher's history
# → Should detect any sample gaps
```

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Start `z_advanced_pub.dart`, wait, start `z_advanced_sub.dart --history` — subscriber receives cached history
3. **Integration test**: Miss detection fires when simulating gaps
4. **Unit test**: AdvancedPublisher with cache options works
5. **Unit test**: AdvancedSubscriber with history options works
6. **Unit test**: Config with timestamp enabled (required for advanced features)
