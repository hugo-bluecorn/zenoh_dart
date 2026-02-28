# Phase 2: z_sub (Callback Subscriber)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0 (Bootstrap) — completed
- C shim: session/config/keyexpr/bytes management
- Dart: `Config`, `Session`, `KeyExpr`, `ZBytes`, `ZenohException`
- Build: CMakeLists links libzenohc, ffigen works

### Phase 1 (z_put + z_delete) — completed
- C shim: `zd_put`, `zd_delete`
- Dart: `Session.put()`, `Session.delete()`
- CLI: `packages/zenoh/bin/z_put.dart`, `packages/zenoh/bin/z_delete.dart`

## This Phase's Goal

Implement a callback-based subscriber. This is the **first phase using the
NativePort callback bridge** — the pattern established here will be reused by
all subsequent callback-based features (queryable, scout, liveliness, etc.).

**Reference example**: `extern/zenoh-c/examples/z_sub.c`

### Key design challenge: Native callbacks → Dart

zenoh-c calls subscriber callbacks on internal zenoh threads. Dart cannot run
code on arbitrary threads. The solution:

1. Dart creates a `ReceivePort` and passes its `sendPort.nativePort` (int64) to C
2. The C shim stores this `Dart_Port` in the callback context
3. When zenoh calls the callback, the C shim serializes sample data into a
   `Dart_CObject` and calls `Dart_PostCObject_DL(port, &obj)`
4. Dart's `ReceivePort.listen()` receives the data on the Dart event loop
5. A `StreamController<Sample>` feeds the data as a Dart `Stream`

## C Shim Functions to Add

### Subscriber declaration

```c
// Declare a subscriber. Samples are posted to the given Dart port.
// Returns 0 on success, negative on error.
FFI_PLUGIN_EXPORT int zd_declare_subscriber(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port);

// Drop (undeclare and free) a subscriber
FFI_PLUGIN_EXPORT void zd_subscriber_drop(z_owned_subscriber_t* subscriber);
```

### Internal callback (not exported)

```c
// Called by zenoh on its internal thread when a sample arrives
static void _zd_sample_callback(z_loaned_sample_t* sample, void* context);
```

This function must:
1. Extract keyexpr string from sample via `z_sample_keyexpr` → `z_keyexpr_as_view_string`
2. Extract payload bytes via `z_sample_payload` → `z_bytes_to_string` (or raw slice)
3. Extract sample kind via `z_sample_kind` (PUT or DELETE)
4. Extract optional attachment via `z_sample_attachment`
5. Package these into a `Dart_CObject` (e.g., an array of typed data)
6. Post to the `Dart_Port` stored in `context`

### Sample data serialization format

The callback posts a `Dart_CObject` array with these elements:
- `[0]` — keyexpr (string)
- `[1]` — payload (Uint8List / typed data)
- `[2]` — sample kind (int: 0 = PUT, 1 = DELETE)
- `[3]` — attachment (Uint8List or null)

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_subscriber` | `z_closure` (macro → concrete closure init), `z_declare_subscriber` |
| `zd_subscriber_drop` | `z_subscriber_drop` + `z_subscriber_move` |
| `_zd_sample_callback` (internal) | `z_sample_keyexpr`, `z_sample_payload`, `z_sample_kind`, `z_sample_attachment`, `z_keyexpr_as_view_string`, `z_bytes_to_string`, `z_string_data`, `z_string_len` |

Additionally uses `Dart_PostCObject_DL` from the Dart native API.

## Dart API Surface

### New file: `packages/zenoh/lib/src/sample.dart`

```dart
/// The kind of a sample (PUT or DELETE).
enum SampleKind { put, delete }

/// A data sample received from a zenoh subscriber.
class Sample {
  final String keyExpr;
  final String payload;  // or ZBytes for raw access
  final SampleKind kind;
  final String? attachment;
}
```

### New file: `packages/zenoh/lib/src/subscriber.dart`

```dart
/// A zenoh subscriber that receives data samples as a stream.
class Subscriber {
  /// Stream of received samples.
  Stream<Sample> get stream;

  /// Undeclare and close the subscriber.
  void close();
}
```

Internal implementation:
- Creates `ReceivePort` in constructor
- Passes `sendPort.nativePort` to `zd_declare_subscriber`
- `ReceivePort.listen()` deserializes data → creates `Sample` objects
- Feeds `StreamController<Sample>` (broadcast)
- `close()` calls `zd_subscriber_drop` and closes the `ReceivePort`

### Modify `packages/zenoh/lib/src/session.dart`

Add method:

```dart
/// Declare a subscriber on a key expression.
Subscriber declareSubscriber(String keyExpr);
```

### Modify `packages/zenoh/lib/zenoh.dart`

Add exports for `Sample`, `SampleKind`, `Subscriber`.

## CLI Example to Create

### `packages/zenoh/bin/z_sub.dart`

Mirrors `extern/zenoh-c/examples/z_sub.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_sub.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>  (default: 'demo/example/**')
```

Behavior:
1. Parse args
2. Open session
3. Declare subscriber on keyexpr
4. Listen to stream, print each sample:
   `>> [Subscriber] Received PUT ('demo/example/key': 'value')`
5. Run until SIGINT (Ctrl-C)
6. Close subscriber and session

## Verification

1. `cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `fvm dart analyze packages/zenoh` — no errors
3. **Integration test (pub->sub)**: Run `packages/zenoh/bin/z_sub.dart` in terminal 1, then
   `packages/zenoh/bin/z_put.dart` in terminal 2 — subscriber should print the received sample
4. **Integration test (delete)**: Run `packages/zenoh/bin/z_sub.dart`, then `packages/zenoh/bin/z_delete.dart` —
   subscriber should print DELETE kind
5. **Unit test**: Declare subscriber, close it, no crash or leak
6. **Unit test**: Verify `Stream<Sample>` closes when subscriber is closed
