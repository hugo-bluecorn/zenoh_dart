# Phase 11: z_liveliness + z_sub_liveliness + z_get_liveliness

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–6 (Core + Query/Reply) — completed
- Session, pub/sub, query/reply, NativePort callback bridge, FIFO reply channels

### Phase 7–10 (SHM Query, Channels, Pull, Querier) — completed
- SHM query/reply, channel patterns, pull subscriber, declared querier

## This Phase's Goal

Implement the liveliness subsystem — a mechanism for tracking the presence of
zenoh entities (peers, services) on the network.

Three related examples:
1. **z_liveliness**: Declares a liveliness token (announces presence)
2. **z_sub_liveliness**: Subscribes to liveliness changes (token alive/dropped)
3. **z_get_liveliness**: Queries currently alive tokens

**Reference examples**:
- `extern/zenoh-c/examples/z_liveliness.c`
- `extern/zenoh-c/examples/z_sub_liveliness.c`
- `extern/zenoh-c/examples/z_get_liveliness.c`

## C Shim Functions to Add

### Liveliness token

```c
// Declare a liveliness token (announces presence on the network).
// Token stays alive until dropped.
FFI_PLUGIN_EXPORT int zd_liveliness_declare_token(
    const z_loaned_session_t* session,
    z_owned_liveliness_token_t* token,
    const z_loaned_keyexpr_t* keyexpr);

// Drop (undeclare) a liveliness token
FFI_PLUGIN_EXPORT void zd_liveliness_token_drop(z_owned_liveliness_token_t* token);
```

### Liveliness subscriber

```c
// Subscribe to liveliness changes. Samples posted to dart_port.
// PUT kind = token alive, DELETE kind = token dropped.
FFI_PLUGIN_EXPORT int zd_liveliness_declare_subscriber(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port,
    bool history);     // if true, receive currently alive tokens as PUT samples

// Uses same zd_subscriber_drop from Phase 2
```

### Liveliness get (query alive tokens)

```c
// Query currently alive liveliness tokens. Replies posted to dart_port.
// Null sentinel at end.
FFI_PLUGIN_EXPORT int zd_liveliness_get(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port,
    uint64_t timeout_ms);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_liveliness_declare_token` | `z_liveliness_declare_token` |
| `zd_liveliness_token_drop` | `z_liveliness_token_drop` (macro) |
| `zd_liveliness_declare_subscriber` | `z_liveliness_declare_subscriber`, `z_liveliness_subscriber_options_default`, `z_closure_sample` |
| `zd_liveliness_get` | `z_liveliness_get`, `z_liveliness_get_options_default`, `z_closure_reply` |

## Dart API Surface

### New file: `packages/zenoh/lib/src/liveliness.dart`

```dart
/// A liveliness token that announces presence on the network.
/// Stays alive until closed (dropped).
class LivelinessToken {
  void close();
}

/// Liveliness operations accessible from a session.
class Liveliness {
  /// Declare a liveliness token.
  LivelinessToken declareToken(String keyExpr);

  /// Subscribe to liveliness changes.
  /// PUT samples = token alive, DELETE samples = token dropped.
  Subscriber declareSubscriber(String keyExpr, {bool history = false});

  /// Query currently alive tokens. Stream completes when done.
  Stream<Reply> get(String keyExpr, {Duration? timeout});
}
```

### Modify `packages/zenoh/lib/src/session.dart`

```dart
class Session {
  /// Access liveliness operations.
  Liveliness get liveliness;
}
```

## CLI Examples to Create

### `packages/zenoh/bin/z_liveliness.dart`

```
Usage: fvm dart run -C packages/zenoh bin/z_liveliness.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>  (default: 'group1/zenoh-dart')
```

Behavior: declare token, sleep until SIGINT, close.

### `packages/zenoh/bin/z_sub_liveliness.dart`

```
Usage: fvm dart run -C packages/zenoh bin/z_sub_liveliness.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'group1/**')
    --history              (flag: receive currently alive tokens)
```

Behavior: subscribe, print alive/dropped events, run until SIGINT.

### `packages/zenoh/bin/z_get_liveliness.dart`

```
Usage: fvm dart run -C packages/zenoh bin/z_get_liveliness.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'group1/**')
    -o, --timeout <MS>     (default: 10000)
```

Behavior: query alive tokens, print results, exit.

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Run `z_sub_liveliness.dart`, then start `z_liveliness.dart` — subscriber sees PUT, stop token — subscriber sees DELETE
3. **Integration test**: Start `z_liveliness.dart`, then `z_get_liveliness.dart` — get returns the alive token
4. **Unit test**: LivelinessToken.close() undeclares cleanly
5. **Unit test**: Liveliness subscriber with history=true sees existing tokens
