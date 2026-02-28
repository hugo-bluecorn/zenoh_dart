# Phase 8: z_queryable_with_channels + z_non_blocking_get

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–6 (Core + Query/Reply) — completed
- Full pub/sub, SHM, discovery, query/reply with clone-and-post pattern
- Dart: Session, Publisher, Subscriber, Queryable, Query, Reply, SHM provider/buffers

### Phase 7 (SHM Query/Reply) — completed
- SHM payloads in queries and replies

## This Phase's Goal

Implement channel-based alternatives to callback-based patterns:

1. **Queryable with FIFO channel**: Instead of a callback that fires for each query,
   use a FIFO channel and explicitly `recv()` queries one at a time
2. **Non-blocking get**: Instead of blocking `recv()` for replies, use `try_recv()`
   polling pattern

These demonstrate zenoh-c's dual approach: callbacks vs channels.

**Reference examples**:
- `extern/zenoh-c/examples/z_queryable_with_channels.c` — FIFO channel queryable
- `extern/zenoh-c/examples/z_non_blocking_get.c` — polling get with try_recv

## C Shim Functions to Add

### FIFO channel for queryable

```c
// Declare a queryable backed by a FIFO channel (no callback).
// Queries are received by polling with zd_fifo_handler_query_recv.
FFI_PLUGIN_EXPORT int zd_declare_queryable_with_fifo_channel(
    const z_loaned_session_t* session,
    z_owned_queryable_t* queryable,
    z_owned_fifo_handler_query_t* handler,
    const z_loaned_keyexpr_t* keyexpr,
    size_t capacity,
    bool complete);

// Blocking receive of next query from FIFO channel.
// Returns 0 on success, Z_CHANNEL_DISCONNECTED when queryable is closed.
FFI_PLUGIN_EXPORT int zd_fifo_handler_query_recv(
    const z_loaned_fifo_handler_query_t* handler,
    z_owned_query_t* query);

// Loan the handler
FFI_PLUGIN_EXPORT const z_loaned_fifo_handler_query_t* zd_fifo_handler_query_loan(
    const z_owned_fifo_handler_query_t* handler);

// Drop the handler
FFI_PLUGIN_EXPORT void zd_fifo_handler_query_drop(
    z_owned_fifo_handler_query_t* handler);
```

### Non-blocking reply receive

```c
// Non-blocking receive of next reply from FIFO handler.
// Returns 0 on success (reply available), Z_CHANNEL_NODATA if empty,
// Z_CHANNEL_DISCONNECTED when query is complete.
FFI_PLUGIN_EXPORT int zd_fifo_handler_reply_try_recv(
    const z_loaned_fifo_handler_reply_t* handler,
    z_owned_reply_t* reply);

// Blocking get with FIFO handler (returns handler for manual recv).
FFI_PLUGIN_EXPORT int zd_get_with_handler(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    const char* parameters,
    z_owned_fifo_handler_reply_t* handler,
    uint64_t timeout_ms,
    int target);

// Loan the reply handler
FFI_PLUGIN_EXPORT const z_loaned_fifo_handler_reply_t* zd_fifo_handler_reply_loan(
    const z_owned_fifo_handler_reply_t* handler);

// Drop the reply handler
FFI_PLUGIN_EXPORT void zd_fifo_handler_reply_drop(
    z_owned_fifo_handler_reply_t* handler);

// Reply accessors (for owned reply from channel recv)
FFI_PLUGIN_EXPORT bool zd_reply_is_ok(const z_owned_reply_t* reply);
FFI_PLUGIN_EXPORT const z_loaned_sample_t* zd_reply_ok(const z_owned_reply_t* reply);
FFI_PLUGIN_EXPORT void zd_reply_drop(z_owned_reply_t* reply);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_declare_queryable_with_fifo_channel` | `z_fifo_channel_query_new`, `z_declare_queryable` |
| `zd_fifo_handler_query_recv` | `z_fifo_handler_query_recv` |
| `zd_fifo_handler_query_loan` | `z_fifo_handler_query_loan` (macro) |
| `zd_fifo_handler_query_drop` | `z_fifo_handler_query_drop` (macro) |
| `zd_fifo_handler_reply_try_recv` | `z_fifo_handler_reply_try_recv` |
| `zd_get_with_handler` | `z_fifo_channel_reply_new`, `z_get` |
| `zd_fifo_handler_reply_loan` | `z_fifo_handler_reply_loan` (macro) |
| `zd_fifo_handler_reply_drop` | `z_fifo_handler_reply_drop` (macro) |
| `zd_reply_is_ok` | `z_reply_is_ok` |
| `zd_reply_ok` | `z_reply_ok` |
| `zd_reply_drop` | `z_reply_drop` (macro) |

## Dart API Surface

### Modify `packages/zenoh/lib/src/session.dart`

Add channel-based alternatives:

```dart
class Session {
  /// Declare a channel-based queryable (polling instead of callbacks).
  ChannelQueryable declareChannelQueryable(
    String keyExpr, {
    int bufferSize = 256,
    bool complete = false,
  });

  /// Non-blocking get — returns a pollable reply receiver.
  ReplyReceiver getNonBlocking(
    String selector, {
    Duration? timeout,
    QueryTarget target = QueryTarget.bestMatching,
  });
}
```

### New additions to existing files or new files

```dart
/// A queryable that receives queries via polling rather than callbacks.
class ChannelQueryable {
  /// Blocking receive of next query. Returns null when closed.
  Query? recv();

  /// Close the queryable.
  void close();
}

/// A reply receiver for non-blocking query results.
class ReplyReceiver {
  /// Non-blocking receive. Returns null if no data available yet.
  /// Throws when all replies have been received (channel disconnected).
  Reply? tryRecv();

  /// Whether the channel is still connected (more replies possible).
  bool get isConnected;

  /// Close and drop the handler.
  void close();
}
```

## CLI Examples to Create

### `packages/zenoh/bin/z_queryable_with_channels.dart`

Mirrors `extern/zenoh-c/examples/z_queryable_with_channels.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_queryable_with_channels.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-queryable')
    -p, --payload <VALUE>  (default: 'Queryable from Dart!')
```

Behavior:
1. Open session
2. Declare channel queryable
3. Loop: recv() query, print info, reply with value
4. Exit when closed

### `packages/zenoh/bin/z_non_blocking_get.dart`

Mirrors `extern/zenoh-c/examples/z_non_blocking_get.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_non_blocking_get.dart [OPTIONS]

Options:
    -s, --selector <SELECTOR>  (default: 'demo/example/**')
    -o, --timeout <MS>         (default: 10000)
```

Behavior:
1. Open session
2. Send query, get reply receiver
3. Poll loop: tryRecv() until disconnected, sleep between polls
4. Print each reply
5. Close

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: `packages/zenoh/bin/z_queryable_with_channels.dart` + `packages/zenoh/bin/z_get.dart` — channel queryable works
3. **Integration test**: `packages/zenoh/bin/z_queryable.dart` + `packages/zenoh/bin/z_non_blocking_get.dart` — non-blocking polling works
4. **Unit test**: ChannelQueryable.recv() returns null after close
5. **Unit test**: ReplyReceiver.tryRecv() returns null when no data, throws on disconnect
