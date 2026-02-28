# Phase 10: z_querier (Declared Querier)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–6 (Core + Query/Reply) — completed
- Session.get() (one-shot query), Queryable, Reply, clone-and-post pattern

### Phase 7–9 (SHM Query, Channels, Pull) — completed
- SHM query/reply, channel-based patterns, pull subscriber

## This Phase's Goal

Implement a declared querier — a long-lived entity for sending repeated queries
to the same key expression. Mirrors how Publisher is to put() — Querier is to get().

Also includes an optional matching status listener (notifies when queryables appear/disappear).

**Reference example**: `extern/zenoh-c/examples/z_querier.c`

## C Shim Functions to Add

```c
// Declare a querier with options
FFI_PLUGIN_EXPORT int zd_declare_querier(
    const z_loaned_session_t* session,
    z_owned_querier_t* querier,
    const z_loaned_keyexpr_t* keyexpr,
    int target,            // z_query_target_t
    uint64_t timeout_ms);

// Issue a query through the querier. Replies posted to dart_port.
// Null sentinel at end.
FFI_PLUGIN_EXPORT int zd_querier_get(
    const z_loaned_querier_t* querier,
    const char* parameters,
    int64_t dart_port,
    z_owned_bytes_t* payload);   // optional, may be NULL

// Loan the querier
FFI_PLUGIN_EXPORT const z_loaned_querier_t* zd_querier_loan(
    const z_owned_querier_t* querier);

// Declare a background matching listener on a querier
FFI_PLUGIN_EXPORT int zd_querier_declare_background_matching_listener(
    const z_loaned_querier_t* querier,
    int64_t dart_port);

// Drop the querier
FFI_PLUGIN_EXPORT void zd_querier_drop(z_owned_querier_t* querier);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_querier` | `z_declare_querier`, `z_querier_options_default` |
| `zd_querier_get` | `z_querier_get`, `z_querier_get_options_default`, `z_fifo_channel_reply_new`, reply closure |
| `zd_querier_loan` | `z_querier_loan` (macro) |
| `zd_querier_declare_background_matching_listener` | `z_querier_declare_background_matching_listener`, `z_closure_matching_status` |
| `zd_querier_drop` | `z_querier_drop` (macro) |

## Dart API Surface

### New file: `packages/zenoh/lib/src/querier.dart`

```dart
/// A declared querier for repeated queries to the same key expression.
class Querier {
  /// Issue a query. Returns a stream of replies that completes when all are received.
  Stream<Reply> get({
    String? parameters,
    ZBytes? payload,
  });

  /// Stream of matching status changes (queryables appearing/disappearing).
  Stream<bool>? get matchingStatus;

  /// Close the querier.
  void close();
}
```

### Modify `packages/zenoh/lib/src/session.dart`

```dart
class Session {
  /// Declare a querier on a key expression.
  Querier declareQuerier(
    String keyExpr, {
    Duration? timeout,
    QueryTarget target = QueryTarget.bestMatching,
    bool enableMatchingListener = false,
  });
}
```

## CLI Example to Create

### `packages/zenoh/bin/z_querier.dart`

Mirrors `extern/zenoh-c/examples/z_querier.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_querier.dart [OPTIONS]

Options:
    -s, --selector <SELECTOR>  (default: 'demo/example/**')
    -p, --payload <VALUE>      (optional)
    -o, --timeout <MS>         (default: 10000)
    --add-matching-listener    (flag)
```

Behavior:
1. Open session
2. Declare querier (with matching listener if flag set)
3. Loop: issue query every 1 second, print replies
4. Run until SIGINT
5. Close

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Run `packages/zenoh/bin/z_queryable.dart` + `packages/zenoh/bin/z_querier.dart` — querier prints periodic replies
3. **Unit test**: Querier.get() stream completes after timeout with no queryable
4. **Unit test**: Matching listener fires when queryable appears/disappears
