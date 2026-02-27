# Phase 7: z_get_shm + z_queryable_shm (SHM Query/Reply)

## Project Context

`zenoh_dart` is a Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–3 (Core Pub/Sub) — completed
- Session/config/keyexpr/bytes, put/delete, subscriber, publisher

### Phase 4 (Core SHM) — completed
- SHM provider, alloc, mutable/immutable buffers, zero-copy bytes, SHM detection
- Dart: `ShmProvider`, `ShmMutBuffer`, `ShmBuffer`, `ZBytes.isShmBacked`

### Phase 5 (Discovery) — completed
- Scout, session info

### Phase 6 (Query/Reply) — completed
- `zd_get`, `zd_declare_queryable`, `zd_query_reply`, clone-and-post query lifecycle
- Dart: `Reply`, `Query`, `Queryable`, `Session.get()`, `Session.declareQueryable()`

## This Phase's Goal

Extend the query/reply pattern with SHM payloads on **both request and response sides**.
A query can carry an SHM payload, and a queryable can reply with SHM-backed bytes.

**Reference examples**:
- `extern/zenoh-c/examples/z_get_shm.c` — sends query with SHM payload via provider
- `extern/zenoh-c/examples/z_queryable_shm.c` — replies with SHM-allocated response buffer

### SHM flow in query/reply

**Requester (z_get_shm)**:
1. Create SHM provider
2. Allocate mutable buffer, write query payload
3. Convert to immutable → to bytes
4. Attach SHM bytes as query payload in `z_get_options_t.payload`

**Responder (z_queryable_shm)**:
1. Receive query, optionally detect if query payload is SHM
2. Allocate SHM buffer from provider for the reply
3. Write response data into buffer
4. Reply with SHM bytes (zero-copy)

## C Shim Functions to Add

### Query with payload

The existing `zd_get` from Phase 6 needs extension to accept an optional payload:

```c
// Send a query with an optional payload (which can be SHM-backed bytes).
// Replies are posted to dart_port. Null sentinel at end.
FFI_PLUGIN_EXPORT int zd_get_with_payload(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    const char* parameters,
    int64_t dart_port,
    uint64_t timeout_ms,
    int target,
    z_owned_bytes_t* payload);       // consumes the payload (may be SHM-backed)
```

Implementation: same as `zd_get` but sets `opts.payload = z_bytes_move(payload)`.

### Query payload detection

```c
// Check if a query's payload is SHM-backed.
// Returns 0 (Z_OK) if SHM-backed, negative otherwise.
FFI_PLUGIN_EXPORT int zd_query_payload_is_shm(const z_owned_query_t* query);
```

### Reply with arbitrary payload (already exists)

The existing `zd_query_reply` from Phase 6 already accepts `z_owned_bytes_t*`
which can be SHM-backed. No new function needed — the SHM transparency works
because `z_bytes_from_shm_mut` produces regular `z_owned_bytes_t`.

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_get_with_payload` | `z_get` with `z_get_options_t.payload` set |
| `zd_query_payload_is_shm` | `z_query_payload` + `z_bytes_as_loaned_shm` |

All other SHM functions from Phase 4 are reused as-is.

## Dart API Surface

### Modify `lib/src/session.dart`

Extend `Session.get()` to accept an optional payload:

```dart
Stream<Reply> get(
  String selector, {
  String? parameters,
  ZBytes? payload,    // NEW — can be SHM-backed
  Duration? timeout,
  QueryTarget target = QueryTarget.bestMatching,
});
```

### Modify `lib/src/query.dart`

The `Query.payload` property (from Phase 6) already returns `ZBytes?`.
Since `ZBytes.isShmBacked` was added in Phase 4, SHM detection on incoming
queries is automatically available:

```dart
query.payload?.isShmBacked  // true if query carries SHM payload
```

### No new files needed

SHM is transparent — existing `ZBytes`, `ShmProvider`, `ShmMutBuffer` compose
with existing `Query.reply()` and `Session.get()`.

## CLI Examples to Create

### `bin/z_get_shm.dart`

Mirrors `extern/zenoh-c/examples/z_get_shm.c`:

```
Usage: dart run bin/z_get_shm.dart [OPTIONS]

Options:
    -s, --selector <SELECTOR>  (default: 'demo/example/**')
    -p, --payload <VALUE>      (default: 'Get from Dart (SHM)!')
    -o, --timeout <MS>         (default: 10000)
```

Behavior:
1. Open session
2. Create SHM provider
3. Allocate buffer, write query payload
4. Convert to bytes (SHM-backed)
5. Send query with SHM payload
6. Print replies
7. Close

### `bin/z_queryable_shm.dart`

Mirrors `extern/zenoh-c/examples/z_queryable_shm.c`:

```
Usage: dart run bin/z_queryable_shm.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-queryable')
    -p, --payload <VALUE>  (default: 'Queryable from Dart (SHM)!')
    --complete             (flag)
```

Behavior:
1. Open session
2. Create SHM provider
3. Declare queryable
4. For each query:
   a. Detect if query payload is SHM
   b. Allocate SHM buffer for reply
   c. Write response value into buffer
   d. Reply with SHM bytes
5. Run until SIGINT
6. Close

## Verification

1. `flutter analyze` — no errors
2. **Integration test**: Run `bin/z_queryable_shm.dart` + `bin/z_get_shm.dart` — end-to-end SHM query/reply
3. **Integration test**: Run Dart `z_queryable_shm.dart` + C `z_get` — cross-language SHM
4. **Integration test**: Run Dart `z_queryable.dart` (non-SHM) + `z_get_shm.dart` — SHM query to non-SHM queryable
5. **Unit test**: `Session.get()` with SHM payload works
6. **Unit test**: `Query.reply()` with SHM bytes works
