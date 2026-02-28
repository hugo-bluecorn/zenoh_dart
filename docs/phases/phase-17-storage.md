# Phase 17: z_storage (In-Memory Storage)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 2 (Subscriber) — completed
- Callback subscriber with `Stream<Sample>`

### Phase 6 (Query/Reply) — completed
- Queryable with `Stream<Query>`, `Query.reply()`

### Phase 0–16 — completed
- All core features including SHM, discovery, channels, serialization

## This Phase's Goal

Implement an in-memory storage that combines a subscriber and a queryable.
The subscriber stores incoming PUT/DELETE samples in a Dart Map, and the
queryable responds to queries by looking up matching entries.

This is a **composite example** — it proves that subscriber and queryable
primitives compose correctly in a real application pattern.

**Reference example**: `extern/zenoh-c/examples/z_storage.c`

### Storage pattern

1. Subscriber listens on `"demo/example/**"` (or configured keyexpr)
2. On PUT: store `(keyexpr → payload)` in a `Map<String, Sample>`
3. On DELETE: remove the entry from the map
4. Queryable on same keyexpr responds to queries:
   - For each stored entry whose keyexpr intersects the query keyexpr
   - Reply with the stored sample's keyexpr and payload

## C Shim Functions to Add

```c
// Clone a sample (for storing in the map — need owned copy)
FFI_PLUGIN_EXPORT int zd_sample_clone(
    z_owned_sample_t* dst,
    const z_loaned_sample_t* src);

// Check if two key expressions intersect
FFI_PLUGIN_EXPORT bool zd_keyexpr_intersects(
    const z_loaned_keyexpr_t* a,
    const z_loaned_keyexpr_t* b);

// Check if a key expression includes another
FFI_PLUGIN_EXPORT bool zd_keyexpr_includes(
    const z_loaned_keyexpr_t* a,
    const z_loaned_keyexpr_t* b);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function |
|----------------|-----------------|
| `zd_sample_clone` | `z_sample_clone` |
| `zd_keyexpr_intersects` | `z_keyexpr_intersects` |
| `zd_keyexpr_includes` | `z_keyexpr_includes` |

## Dart API Surface

### Modify `packages/zenoh/lib/src/keyexpr.dart`

```dart
class KeyExpr {
  /// Check if this key expression intersects another.
  bool intersects(KeyExpr other);

  /// Check if this key expression includes another.
  bool includes(KeyExpr other);
}
```

### No other new API needed

The storage example composes existing subscriber + queryable.

## CLI Example to Create

### `packages/zenoh/bin/z_storage.dart`

Mirrors `extern/zenoh-c/examples/z_storage.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_storage.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>  (default: 'demo/example/**')
```

Behavior:
1. Open session
2. Create in-memory store: `Map<String, String>` (keyexpr → payload)
3. Declare subscriber on keyexpr:
   - On PUT: `store[keyExpr] = payload`; print `[Storage] Stored ('keyexpr': 'value')`
   - On DELETE: `store.remove(keyExpr)`; print `[Storage] Deleted 'keyexpr'`
4. Declare queryable on same keyexpr:
   - For each query: iterate store entries, reply with entries whose keyexpr
     intersects the query keyexpr
5. Run until SIGINT
6. Close subscriber, queryable, session

### Usage scenario

```bash
# Terminal 1: Start storage
fvm dart run -C packages/zenoh bin/z_storage.dart

# Terminal 2: Put some data
fvm dart run -C packages/zenoh bin/z_put.dart -k "demo/example/key1" -p "value1"
fvm dart run -C packages/zenoh bin/z_put.dart -k "demo/example/key2" -p "value2"

# Terminal 3: Query the storage
fvm dart run -C packages/zenoh bin/z_get.dart -s "demo/example/**"
# → Should return both key1 and key2 with their values

# Terminal 2: Delete a key
fvm dart run -C packages/zenoh bin/z_delete.dart -k "demo/example/key1"

# Terminal 3: Query again
fvm dart run -C packages/zenoh bin/z_get.dart -s "demo/example/**"
# → Should return only key2
```

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Unit test**: `KeyExpr.intersects()` with matching keyexprs returns true
3. **Unit test**: `KeyExpr.intersects()` with non-matching keyexprs returns false
4. **Unit test**: `KeyExpr.includes()` works correctly
5. **Integration test**: Full scenario above — put, query, delete, query again
6. **Integration test**: Use C `z_put` and C `z_get` with Dart storage
