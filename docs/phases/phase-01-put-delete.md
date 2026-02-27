# Phase 1: z_put + z_delete (One-shot Publish)

## Project Context

`zenoh_dart` is a Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

### Architecture (abbreviated)

```
Dart CLI example (bin/z_*.dart)  →  Idiomatic Dart API (lib/src/*.dart)
  →  Generated FFI bindings (lib/src/bindings.dart)  →  C shim (src/zenoh_dart.h/.c)
  →  libzenohc.so
```

## Prior Phases

### Phase 0 (Bootstrap) — completed

Available infrastructure:
- **C shim**: `zd_init_dart_api_dl`, `zd_init_log`, `zd_config_default`, `zd_config_insert_json5`, `zd_open_session`, `zd_close_session`, `zd_session_loan`, `zd_view_keyexpr_from_str`, `zd_view_keyexpr_loan`, `zd_keyexpr_as_view_string`, `zd_bytes_copy_from_str`, `zd_bytes_from_static_str`, `zd_bytes_copy_from_buf`, `zd_bytes_to_string`, `zd_bytes_loan`, `zd_bytes_drop`, `zd_string_data`, `zd_string_len`, `zd_string_drop`
- **Dart classes**: `Config`, `Session` (open/close), `KeyExpr`, `ZBytes`, `ZenohException`
- **Build**: CMakeLists links libzenohc, ffigen generates bindings
- **Files**: `lib/src/bindings.dart`, `lib/src/native_lib.dart`, `lib/src/exceptions.dart`, `lib/src/config.dart`, `lib/src/session.dart`, `lib/src/keyexpr.dart`, `lib/src/bytes.dart`, `lib/zenoh_dart.dart`

## This Phase's Goal

Implement the simplest zenoh operations: one-shot `put` and `delete`. These are
the most basic session operations — no callbacks, no long-lived entities.

**Reference examples**:
- `extern/zenoh-c/examples/z_put.c` — opens session, puts data to keyexpr, closes
- `extern/zenoh-c/examples/z_delete.c` — opens session, deletes keyexpr, closes

## C Shim Functions to Add

Add to `src/zenoh_dart.h` and implement in `src/zenoh_dart.c`:

```c
// Put data on a key expression (one-shot, no publisher needed)
// Returns 0 on success, negative on error
FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload);

// Delete a key expression (one-shot)
// Returns 0 on success, negative on error
FFI_PLUGIN_EXPORT int zd_delete(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr);
```

### Implementation notes

`zd_put` wraps:
```c
int zd_put(const z_loaned_session_t* session, const z_loaned_keyexpr_t* keyexpr,
           z_owned_bytes_t* payload) {
    return z_put(session, keyexpr, z_bytes_move(payload), NULL);
}
```

`zd_delete` wraps:
```c
int zd_delete(const z_loaned_session_t* session, const z_loaned_keyexpr_t* keyexpr) {
    return z_delete(session, keyexpr, NULL);
}
```

The `NULL` options parameter means default options (no encoding, no attachment, etc.).

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function |
|----------------|-----------------|
| `zd_put` | `z_put` + `z_bytes_move` |
| `zd_delete` | `z_delete` |

## Dart API Surface

### Modify `lib/src/session.dart`

Add methods to `Session`:

```dart
/// Put a string value on a key expression (one-shot).
void put(String keyExpr, String value);

/// Put bytes on a key expression (one-shot).
void putBytes(String keyExpr, ZBytes payload);

/// Delete a key expression (one-shot).
void delete(String keyExpr);
```

### No new files needed

All new API is added to the existing `Session` class.

## CLI Examples to Create

### `bin/z_put.dart`

Mirrors `extern/zenoh-c/examples/z_put.c`:

```
Usage: dart run bin/z_put.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-put')
    -p, --payload <VALUE>  (default: 'Put from Dart!')
```

Behavior:
1. Parse args
2. Open session with default config
3. Put value on keyexpr
4. Print confirmation
5. Close session

### `bin/z_delete.dart`

Mirrors `extern/zenoh-c/examples/z_delete.c`:

```
Usage: dart run bin/z_delete.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-put')
```

Behavior:
1. Parse args
2. Open session with default config
3. Delete keyexpr
4. Print confirmation
5. Close session

## Verification

1. `dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `flutter analyze` — no errors
3. **Integration test**: Run `bin/z_put.dart` while a zenoh-c `z_sub` subscriber is running — subscriber should print the PUT
4. **Integration test**: Run `bin/z_delete.dart` while a zenoh-c `z_sub` subscriber is running — subscriber should print DELETE
5. **Unit test**: `Session.put()` with invalid keyexpr throws `ZenohException`
6. **Unit test**: `Session.delete()` with valid keyexpr succeeds (return 0)
