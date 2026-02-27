# Phase 3: z_pub (Declared Publisher)

## Project Context

`zenoh_dart` is a Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0 (Bootstrap) — completed
- C shim: session/config/keyexpr/bytes management
- Dart: `Config`, `Session`, `KeyExpr`, `ZBytes`, `ZenohException`

### Phase 1 (z_put + z_delete) — completed
- C shim: `zd_put`, `zd_delete`
- Dart: `Session.put()`, `Session.delete()`

### Phase 2 (z_sub) — completed
- C shim: `zd_declare_subscriber`, `zd_subscriber_drop`, NativePort callback bridge
- Dart: `Sample`, `SampleKind`, `Subscriber` with `Stream<Sample>`
- CLI: `bin/z_sub.dart`

## This Phase's Goal

Implement a declared publisher — a long-lived entity that efficiently publishes
multiple messages to the same key expression. Also adds the optional matching
status listener (notifies when subscribers appear/disappear).

**Reference example**: `extern/zenoh-c/examples/z_pub.c`

## C Shim Functions to Add

### Publisher declaration and operations

```c
// Declare a publisher on a key expression with default options
FFI_PLUGIN_EXPORT int zd_declare_publisher(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr);

// Declare a publisher with options (encoding, congestion control, priority)
FFI_PLUGIN_EXPORT int zd_declare_publisher_with_opts(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    const z_publisher_options_t* options);

// Get default publisher options
FFI_PLUGIN_EXPORT void zd_publisher_options_default(z_publisher_options_t* options);

// Publish data through a declared publisher
FFI_PLUGIN_EXPORT int zd_publisher_put(
    const z_loaned_publisher_t* publisher,
    z_owned_bytes_t* payload);

// Publish with options (encoding, attachment)
FFI_PLUGIN_EXPORT int zd_publisher_put_with_opts(
    const z_loaned_publisher_t* publisher,
    z_owned_bytes_t* payload,
    const z_publisher_put_options_t* options);

// Get default publisher put options
FFI_PLUGIN_EXPORT void zd_publisher_put_options_default(z_publisher_put_options_t* options);

// Get a loaned reference to the publisher
FFI_PLUGIN_EXPORT const z_loaned_publisher_t* zd_publisher_loan(
    const z_owned_publisher_t* publisher);

// Drop (undeclare and free) a publisher
FFI_PLUGIN_EXPORT void zd_publisher_drop(z_owned_publisher_t* publisher);
```

### Matching status listener

```c
// Declare a background matching listener on a publisher.
// Matching status changes are posted to dart_port.
// Posts: int (1 = matching, 0 = not matching)
FFI_PLUGIN_EXPORT int zd_publisher_declare_background_matching_listener(
    const z_loaned_publisher_t* publisher,
    int64_t dart_port);
```

Internal callback serializes `z_matching_status_t.matching` (bool) and posts to port.

### Encoding helpers

```c
// Get a pointer to a predefined encoding constant (e.g., text/plain)
FFI_PLUGIN_EXPORT const z_loaned_encoding_t* zd_encoding_text_plain(void);
FFI_PLUGIN_EXPORT const z_loaned_encoding_t* zd_encoding_application_octet_stream(void);
FFI_PLUGIN_EXPORT const z_loaned_encoding_t* zd_encoding_application_json(void);

// Clone an encoding
FFI_PLUGIN_EXPORT void zd_encoding_clone(
    z_owned_encoding_t* dst, const z_loaned_encoding_t* src);

// Drop an encoding
FFI_PLUGIN_EXPORT void zd_encoding_drop(z_owned_encoding_t* encoding);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_publisher` | `z_declare_publisher` |
| `zd_declare_publisher_with_opts` | `z_declare_publisher` with `z_publisher_options_t` |
| `zd_publisher_options_default` | `z_publisher_options_default` |
| `zd_publisher_put` | `z_publisher_put` + `z_bytes_move` |
| `zd_publisher_put_with_opts` | `z_publisher_put` with `z_publisher_put_options_t` |
| `zd_publisher_put_options_default` | `z_publisher_put_options_default` |
| `zd_publisher_loan` | `z_publisher_loan` (macro → concrete) |
| `zd_publisher_drop` | `z_publisher_drop` + `z_publisher_move` |
| `zd_publisher_declare_background_matching_listener` | `z_publisher_declare_background_matching_listener` + `z_closure_matching_status` |
| `zd_encoding_text_plain` | `z_encoding_text_plain` |
| `zd_encoding_clone` | `z_encoding_clone` |

## Dart API Surface

### New file: `lib/src/publisher.dart`

```dart
/// A declared zenoh publisher for efficient repeated publishing.
class Publisher {
  /// Publish a string value.
  void put(String value);

  /// Publish raw bytes.
  void putBytes(ZBytes payload);

  /// Stream of matching status changes (subscribers appearing/disappearing).
  /// Only available if matching listener was requested at declaration time.
  Stream<bool>? get matchingStatus;

  /// Undeclare and close the publisher.
  void close();
}
```

### New file: `lib/src/encoding.dart`

```dart
/// Content encoding for zenoh payloads.
class Encoding {
  static final Encoding textPlain = ...;
  static final Encoding applicationOctetStream = ...;
  static final Encoding applicationJson = ...;
}
```

### Modify `lib/src/session.dart`

Add method:

```dart
/// Declare a publisher on a key expression.
Publisher declarePublisher(
  String keyExpr, {
  Encoding? encoding,
  bool enableMatchingListener = false,
});
```

### Modify `lib/zenoh_dart.dart`

Add exports for `Publisher`, `Encoding`.

## CLI Example to Create

### `bin/z_pub.dart`

Mirrors `extern/zenoh-c/examples/z_pub.c`:

```
Usage: dart run bin/z_pub.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>           (default: 'demo/example/zenoh-dart-pub')
    -p, --payload <VALUE>         (default: 'Pub from Dart!')
    -a, --attach <ATTACHMENT>     (optional)
    --add-matching-listener       (optional, enables matching status)
```

Behavior:
1. Parse args
2. Open session
3. Declare publisher (with matching listener if flag set)
4. Loop: publish `"[<idx>] <value>"` every second
5. If matching listener: print matching status changes
6. Run until SIGINT
7. Close publisher and session

## Verification

1. `dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `flutter analyze` — no errors
3. **Integration test**: Run `bin/z_sub.dart` in terminal 1, `bin/z_pub.dart` in terminal 2 — subscriber prints periodic messages with index
4. **Integration test**: Run `bin/z_pub.dart --add-matching-listener`, then start/stop `bin/z_sub.dart` — publisher prints matching status changes
5. **Unit test**: Declare publisher, put once, close — no crash
6. **Unit test**: Publisher with encoding option works
