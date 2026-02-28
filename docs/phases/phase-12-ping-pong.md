# Phase 12: z_pong + z_ping (Latency Test)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–3 (Core Pub/Sub) — completed
- Publisher, Subscriber (callback-based)

### Phase 4–11 (SHM, Discovery, Query, Channels, Pull, Querier, Liveliness) — completed
- All core features, SHM provider, channel patterns

## This Phase's Goal

Implement the ping/pong latency benchmark. This requires:
- **Background subscriber**: A subscriber that runs without explicit management
- **Raw byte payloads**: Arbitrary byte arrays (not just strings)
- **Publisher express mode**: Disables message batching for lower latency

**Reference examples**:
- `extern/zenoh-c/examples/z_pong.c` — subscribes to "test/ping", echoes back on "test/pong"
- `extern/zenoh-c/examples/z_ping.c` — publishes to "test/ping", measures RTT from "test/pong"

### Pattern

```
z_ping                          z_pong
  |                               |
  |-- pub "test/ping" payload --> |
  |                               |-- sub receives, echoes payload
  |<-- sub "test/pong" payload -- |-- pub "test/pong" same payload
  |                               |
  |  measure RTT                  |
```

## C Shim Functions to Add

### Background subscriber

```c
// Declare a background subscriber (no handle returned, no explicit management).
// Samples posted to dart_port. Subscriber lives until session closes.
FFI_PLUGIN_EXPORT int zd_declare_background_subscriber(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port);
```

### Raw byte operations

```c
// Create bytes from a raw buffer (copies data)
// Already exists from Phase 0: zd_bytes_copy_from_buf

// Clone bytes (shallow reference copy — important for SHM reuse)
FFI_PLUGIN_EXPORT void zd_bytes_clone(
    z_owned_bytes_t* dst,
    const z_loaned_bytes_t* src);

// Get bytes as raw slice for reading
FFI_PLUGIN_EXPORT int zd_bytes_to_slice(
    const z_loaned_bytes_t* bytes,
    z_owned_slice_t* out);

// Slice accessors
FFI_PLUGIN_EXPORT const uint8_t* zd_slice_data(const z_loaned_slice_t* slice);
FFI_PLUGIN_EXPORT size_t zd_slice_len(const z_loaned_slice_t* slice);
FFI_PLUGIN_EXPORT void zd_slice_drop(z_owned_slice_t* slice);
```

### Publisher express mode

```c
// Set express flag on publisher options (disables batching)
// Modify zd_publisher_options or add to existing options struct
// The z_publisher_options_t already has an is_express field
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_background_subscriber` | `z_declare_background_subscriber`, `z_closure_sample` |
| `zd_bytes_clone` | `z_bytes_clone` |
| `zd_bytes_to_slice` | `z_bytes_to_slice` |
| `zd_slice_data` | `z_slice_data` |
| `zd_slice_len` | `z_slice_len` |
| `zd_slice_drop` | `z_slice_drop` (macro) |

## Dart API Surface

### Modify `packages/zenoh/lib/src/session.dart`

```dart
class Session {
  /// Declare a background subscriber (lives until session closes).
  /// Returns a stream of samples.
  Stream<Sample> declareBackgroundSubscriber(String keyExpr);
}
```

### Modify `packages/zenoh/lib/src/bytes.dart`

```dart
class ZBytes {
  /// Clone these bytes (shallow reference copy for SHM, deep copy for RAW).
  ZBytes clone();

  /// Convert to raw byte array.
  Uint8List toBytes();
}
```

### Modify `packages/zenoh/lib/src/publisher.dart`

Add `isExpress` parameter to publisher declaration:

```dart
Publisher declarePublisher(
  String keyExpr, {
  Encoding? encoding,
  bool isExpress = false,   // NEW
  bool enableMatchingListener = false,
});
```

## CLI Examples to Create

### `packages/zenoh/bin/z_pong.dart`

Mirrors `extern/zenoh-c/examples/z_pong.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_pong.dart
```

Behavior:
1. Open session
2. Declare publisher on "test/pong"
3. Declare background subscriber on "test/ping"
4. For each received sample: clone payload, publish on "test/pong"
5. Run until SIGINT

### `packages/zenoh/bin/z_ping.dart`

Mirrors `extern/zenoh-c/examples/z_ping.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_ping.dart [OPTIONS]

Options:
    -p, --payload-size <SIZE>  (default: 8)
    -n, --samples <NUM>        (default: 100)
    -w, --warmup <MS>          (default: 1000)
```

Behavior:
1. Open session
2. Declare publisher on "test/ping" (express mode)
3. Declare subscriber on "test/pong" (with Completer for synchronization)
4. Create payload of given size
5. Warmup phase: publish+wait for warmup duration
6. Measurement phase: for each ping:
   a. Record start time (Stopwatch)
   b. Publish payload
   c. Wait for pong response (Completer)
   d. Record elapsed time
7. Print results (RTT per sample, one-way latency)
8. Close

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Run `packages/zenoh/bin/z_pong.dart` + `packages/zenoh/bin/z_ping.dart` — ping prints latency results
3. **Integration test**: Run C `z_pong` + Dart `z_ping.dart` — cross-language latency
4. **Unit test**: `ZBytes.clone()` produces independent copy
5. **Unit test**: `ZBytes.toBytes()` returns correct raw bytes
6. **Unit test**: Background subscriber receives samples
