# Phase 9: z_pull (Ring Channel Subscriber)

## Project Context

`zenoh_dart` is a Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–3 (Core Pub/Sub) — completed
- Session, publisher, subscriber (callback-based)

### Phase 4–8 (SHM, Discovery, Query, Channels) — completed
- SHM provider, scout/info, query/reply, channel-based patterns

## This Phase's Goal

Implement a pull-based subscriber using a ring buffer channel. Unlike the
callback subscriber (Phase 2) which pushes every sample, the pull subscriber
stores samples in a ring buffer and the application explicitly polls for them.

Key behaviors:
- Ring buffer has configurable capacity
- `try_recv()` returns the latest sample or null if empty
- Older samples are dropped when buffer is full (ring semantics)

**Reference example**: `extern/zenoh-c/examples/z_pull.c`

## C Shim Functions to Add

```c
// Declare a subscriber with a ring buffer channel.
// Returns 0 on success, negative on error.
FFI_PLUGIN_EXPORT int zd_declare_subscriber_with_ring_channel(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    z_owned_ring_handler_sample_t* handler,
    const z_loaned_keyexpr_t* keyexpr,
    size_t capacity);

// Non-blocking receive from ring channel.
// Returns 0 on success (sample available), Z_CHANNEL_NODATA if empty,
// Z_CHANNEL_DISCONNECTED when subscriber is closed.
FFI_PLUGIN_EXPORT int zd_ring_handler_sample_try_recv(
    const z_loaned_ring_handler_sample_t* handler,
    z_owned_sample_t* sample);

// Loan the handler
FFI_PLUGIN_EXPORT const z_loaned_ring_handler_sample_t* zd_ring_handler_sample_loan(
    const z_owned_ring_handler_sample_t* handler);

// Drop the handler
FFI_PLUGIN_EXPORT void zd_ring_handler_sample_drop(
    z_owned_ring_handler_sample_t* handler);

// Sample accessors for owned samples from channel (not loaned from callback)
FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_sample_keyexpr(const z_owned_sample_t* sample);
FFI_PLUGIN_EXPORT const z_loaned_bytes_t* zd_sample_payload(const z_owned_sample_t* sample);
FFI_PLUGIN_EXPORT int zd_sample_kind(const z_owned_sample_t* sample);
FFI_PLUGIN_EXPORT void zd_sample_drop(z_owned_sample_t* sample);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_subscriber_with_ring_channel` | `z_ring_channel_sample_new`, `z_declare_subscriber` |
| `zd_ring_handler_sample_try_recv` | `z_ring_handler_sample_try_recv` |
| `zd_ring_handler_sample_loan` | `z_ring_handler_sample_loan` (macro) |
| `zd_ring_handler_sample_drop` | `z_ring_handler_sample_drop` (macro) |
| `zd_sample_keyexpr` | `z_sample_keyexpr` |
| `zd_sample_payload` | `z_sample_payload` |
| `zd_sample_kind` | `z_sample_kind` |
| `zd_sample_drop` | `z_sample_drop` (macro) |

## Dart API Surface

### New class (in existing or new file)

```dart
/// A pull-based subscriber backed by a ring buffer.
/// Samples are buffered and retrieved by polling.
class PullSubscriber {
  /// Non-blocking receive of the latest sample.
  /// Returns null if no sample is available.
  Sample? tryRecv();

  /// Whether the subscriber is still active.
  bool get isConnected;

  /// Close the subscriber and its ring buffer.
  void close();
}
```

### Modify `lib/src/session.dart`

```dart
class Session {
  /// Declare a pull-based subscriber with a ring buffer.
  PullSubscriber declarePullSubscriber(
    String keyExpr, {
    int bufferSize = 256,
  });
}
```

## CLI Example to Create

### `bin/z_pull.dart`

Mirrors `extern/zenoh-c/examples/z_pull.c`:

```
Usage: dart run bin/z_pull.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>      (default: 'demo/example/**')
    -s, --size <RING_SIZE>   (default: 3)
```

Behavior:
1. Open session
2. Declare pull subscriber with ring buffer
3. Loop: poll every 1 second, print sample if available
4. Run until SIGINT
5. Close

## Verification

1. `flutter analyze` — no errors
2. **Integration test**: Run `bin/z_pull.dart` + `bin/z_pub.dart` — pull subscriber receives periodic samples
3. **Unit test**: PullSubscriber.tryRecv() returns null when empty
4. **Unit test**: Ring buffer drops old samples when full
5. **Unit test**: PullSubscriber.isConnected returns false after close
