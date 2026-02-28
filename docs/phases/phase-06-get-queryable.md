# Phase 6: z_get + z_queryable (Query/Reply)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–3 (Core Pub/Sub) — completed
- Session/config/keyexpr/bytes, put/delete, subscriber (NativePort), publisher

### Phase 4 (Core SHM) — completed
- SHM provider, alloc, buffers, zero-copy publish, SHM detection

### Phase 5 (Discovery) — completed
- Scout, session info (ZenohId, Hello)

## This Phase's Goal

Implement the query/reply pattern — the most architecturally complex phase.
A "get" sends a query, and a "queryable" declares a handler that receives
queries and sends replies.

**Reference examples**:
- `extern/zenoh-c/examples/z_get.c` — sends a query, receives replies via FIFO channel
- `extern/zenoh-c/examples/z_queryable.c` — handles queries with a callback, sends replies

### Key design challenge: Query lifecycle

Unlike subscribers (fire-and-forget callbacks), queryables must **reply** to
queries. The query is only valid during the callback in zenoh-c. Two approaches:

**Chosen: Clone-and-post**
1. C callback receives `z_loaned_query_t`
2. Calls `z_query_clone` to create an owned `z_owned_query_t` on the heap
3. Posts a pointer/handle to Dart via NativePort
4. Dart processes the query, calls back to C: `zd_query_reply(handle, keyexpr, payload)`
5. Dart calls `zd_query_drop(handle)` when done

This decouples the callback thread from Dart's event loop while keeping the
query alive for as long as needed.

## C Shim Functions to Add

### Query (get) side

```c
// Send a query. Replies are posted to dart_port.
// A null/sentinel is posted when all replies have been received.
// Returns 0 on success, negative on error.
FFI_PLUGIN_EXPORT int zd_get(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    const char* parameters,       // selector parameters (may be NULL)
    int64_t dart_port,
    uint64_t timeout_ms,          // 0 = default timeout
    int target);                  // z_query_target_t enum value
```

Internal implementation creates a `z_owned_closure_reply_t` that:
1. For each reply: extracts is_ok, sample (keyexpr, payload, kind), or error → posts to dart_port
2. The closure's drop function posts a null sentinel to signal completion

Reply serialization format posted to port:
- `[0]` — is_ok (bool/int: 1 = ok, 0 = error)
- For ok replies: `[1]` keyexpr string, `[2]` payload bytes, `[3]` kind int
- For error replies: `[1]` error payload bytes, `[2]` error encoding string
- Sentinel: `null` (end of replies)

### Queryable side

```c
// Declare a queryable. Incoming queries are posted to dart_port as handles.
// Returns 0 on success, negative on error.
FFI_PLUGIN_EXPORT int zd_declare_queryable(
    const z_loaned_session_t* session,
    z_owned_queryable_t* queryable,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port,
    bool complete);

// Reply to a query (the query must have been cloned in the callback).
// Returns 0 on success.
FFI_PLUGIN_EXPORT int zd_query_reply(
    z_owned_query_t* query,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload);

// Drop a cloned query (must be called after reply or if skipping reply).
FFI_PLUGIN_EXPORT void zd_query_drop(z_owned_query_t* query);

// Get the key expression from a cloned query
FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_query_keyexpr(const z_owned_query_t* query);

// Get the parameters string from a cloned query
FFI_PLUGIN_EXPORT const z_loaned_string_t* zd_query_parameters(const z_owned_query_t* query);

// Get the payload from a cloned query (may be NULL if no payload)
FFI_PLUGIN_EXPORT const z_loaned_bytes_t* zd_query_payload(const z_owned_query_t* query);

// Drop (undeclare) a queryable
FFI_PLUGIN_EXPORT void zd_queryable_drop(z_owned_queryable_t* queryable);
```

Internal `_zd_query_callback` implementation:
1. Receives `z_loaned_query_t*` from zenoh
2. Calls `z_query_clone(&owned_query, query)` to create heap-allocated copy
3. Extracts keyexpr, parameters, optional payload from the cloned query
4. Posts to dart_port: `[query_ptr, keyexpr_string, params_string, payload_bytes_or_null]`

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_get` | `z_get`, `z_get_options_default`, `z_closure_reply` |
| `zd_declare_queryable` | `z_declare_queryable`, `z_queryable_options_default`, `z_closure_query`, `z_query_clone` |
| `zd_query_reply` | `z_query_reply`, `z_query_reply_options_default` |
| `zd_query_drop` | `z_query_drop` + `z_query_move` |
| `zd_query_keyexpr` | `z_query_keyexpr` |
| `zd_query_parameters` | `z_query_parameters` |
| `zd_query_payload` | `z_query_payload` |
| `zd_queryable_drop` | `z_queryable_drop` + `z_queryable_move` |
| (internal: reply callback) | `z_reply_is_ok`, `z_reply_ok`, `z_reply_err`, `z_sample_keyexpr`, `z_sample_payload`, `z_sample_kind` |

## Dart API Surface

### New file: `packages/zenoh/lib/src/reply.dart`

```dart
/// A reply received from a query.
class Reply {
  /// Whether this reply contains a successful sample.
  bool get isOk;

  /// The sample from a successful reply.
  Sample? get ok;

  /// The error from a failed reply.
  ReplyError? get error;
}

/// Error information from a failed reply.
class ReplyError {
  final ZBytes payload;
  final String? encoding;
}
```

### New file: `packages/zenoh/lib/src/query.dart`

```dart
/// A query received by a queryable.
class Query {
  /// The key expression of the query.
  String get keyExpr;

  /// The query parameters (selector part after '?').
  String get parameters;

  /// Optional payload attached to the query.
  ZBytes? get payload;

  /// Reply to this query with a value.
  void reply(String keyExpr, String value);

  /// Reply to this query with bytes.
  void replyBytes(String keyExpr, ZBytes payload);
}
```

### New file: `packages/zenoh/lib/src/queryable.dart`

```dart
/// A queryable that handles incoming queries.
class Queryable {
  /// Stream of incoming queries.
  Stream<Query> get stream;

  /// Undeclare and close the queryable.
  void close();
}
```

### New file: `packages/zenoh/lib/src/enums.dart`

```dart
/// Target for query routing.
enum QueryTarget {
  bestMatching,  // Z_QUERY_TARGET_BEST_MATCHING
  all,           // Z_QUERY_TARGET_ALL
  allComplete,   // Z_QUERY_TARGET_ALL_COMPLETE
}
```

### Modify `packages/zenoh/lib/src/session.dart`

Add methods:

```dart
class Session {
  /// Send a query and receive replies as a stream.
  /// The stream completes when all replies have been received.
  Stream<Reply> get(
    String selector, {
    String? parameters,
    Duration? timeout,
    QueryTarget target = QueryTarget.bestMatching,
  });

  /// Declare a queryable on a key expression.
  Queryable declareQueryable(
    String keyExpr, {
    bool complete = false,
  });
}
```

### Modify `packages/zenoh/lib/zenoh.dart`

Add exports for `Reply`, `ReplyError`, `Query`, `Queryable`, `QueryTarget`.

## CLI Examples to Create

### `packages/zenoh/bin/z_queryable.dart`

Mirrors `extern/zenoh-c/examples/z_queryable.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_queryable.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-queryable')
    -p, --payload <VALUE>  (default: 'Queryable from Dart!')
    --complete             (flag: declare as complete queryable)
```

Behavior:
1. Open session
2. Declare queryable
3. For each query: print keyexpr + params, reply with fixed value
4. Run until SIGINT
5. Close

### `packages/zenoh/bin/z_get.dart`

Mirrors `extern/zenoh-c/examples/z_get.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_get.dart [OPTIONS]

Options:
    -s, --selector <SELECTOR>  (default: 'demo/example/**')
    -p, --payload <VALUE>      (optional: payload to send with query)
    -t, --target <TARGET>      (optional: BEST_MATCHING | ALL | ALL_COMPLETE)
    -o, --timeout <MS>         (default: 10000)
```

Behavior:
1. Open session
2. Send query
3. Print each reply (ok or error)
4. Close session when stream completes

## Verification

1. `cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `fvm dart analyze packages/zenoh` — no errors
3. **Integration test**: Run `packages/zenoh/bin/z_queryable.dart` in terminal 1, `packages/zenoh/bin/z_get.dart` in terminal 2 — get prints the reply
4. **Integration test**: Run with zenoh-c `z_queryable` and Dart `z_get.dart` (cross-language)
5. **Unit test**: Query stream completes (finite) after timeout with no queryable
6. **Unit test**: Queryable stream produces queries, reply works, drop works
7. **Unit test**: Query.reply() called, then Query is automatically dropped
