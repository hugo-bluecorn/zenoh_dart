# Phase 4: SHM Provider + z_pub_shm + z_sub_shm (Core SHM)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

**SHM (Shared Memory) is a first-class feature** — it is the primary reason for
building dart:ffi bindings rather than using a higher-level approach. SHM enables
zero-copy data transfer between zenoh peers on the same machine.

## Prior Phases

### Phase 0 (Bootstrap) — completed
- C shim: session/config/keyexpr/bytes management, Dart native API DL init
- Dart: `Config`, `Session`, `KeyExpr`, `ZBytes`, `ZenohException`

### Phase 1 (z_put + z_delete) — completed
- C shim: `zd_put`, `zd_delete`
- Dart: `Session.put()`, `Session.delete()`

### Phase 2 (z_sub) — completed
- C shim: `zd_declare_subscriber`, NativePort callback bridge
- Dart: `Sample`, `Subscriber` with `Stream<Sample>`

### Phase 3 (z_pub) — completed
- C shim: `zd_declare_publisher*`, `zd_publisher_put*`, matching listener
- Dart: `Publisher`, `Encoding`

## This Phase's Goal

Introduce the **SHM provider infrastructure** — the foundation for all SHM
operations — and implement SHM-based publishing and subscribing.

**Reference examples**:
- `extern/zenoh-c/examples/z_pub_shm.c` — allocates SHM buffer, writes data, publishes
- `extern/zenoh-c/examples/z_sub_shm.c` — receives samples, detects SHM vs RAW buffers

### SHM concepts

1. **SHM Provider**: Manages a POSIX shared memory pool. Created with a total size.
2. **Allocation**: Request buffer from provider. Multiple strategies:
   - `alloc` — simple, may fail if pool is full
   - `alloc_gc_defrag_blocking` — garbage collects, defragments, blocks until space available
3. **Mutable buffer** (`z_owned_shm_mut_t`): Writable buffer, get raw pointer via `data_mut()`
4. **Immutable buffer** (`z_owned_shm_t`): Read-only, converted from mutable
5. **Bytes conversion**: SHM buffers convert to `z_owned_bytes_t` for publishing (zero-copy)
6. **Receive-side detection**: Subscriber can detect if received payload is SHM-backed

### zenoh-c SHM build requirement

libzenohc must be built with:
- `-DZENOHC_BUILD_WITH_SHARED_MEMORY=TRUE`
- `-DZENOHC_BUILD_WITH_UNSTABLE_API=TRUE`

This enables `Z_FEATURE_SHARED_MEMORY` and `Z_FEATURE_UNSTABLE_API` compile-time flags.

## C Shim Functions to Add

### SHM Provider

```c
// Create a default POSIX SHM provider with given total pool size
FFI_PLUGIN_EXPORT int zd_shm_provider_default_new(
    z_owned_shm_provider_t* provider,
    size_t total_size);

// Get a loaned reference to the provider
FFI_PLUGIN_EXPORT const z_loaned_shm_provider_t* zd_shm_provider_loan(
    const z_owned_shm_provider_t* provider);

// Drop (free) the SHM provider
FFI_PLUGIN_EXPORT void zd_shm_provider_drop(z_owned_shm_provider_t* provider);
```

### SHM Allocation

```c
// Basic allocation — may fail if pool is full
FFI_PLUGIN_EXPORT int zd_shm_provider_alloc(
    z_buf_layout_alloc_result_t* result,
    const z_loaned_shm_provider_t* provider,
    size_t size);

// Allocation with garbage collection, defragmentation, and blocking
// Blocks until space is available (safest strategy)
FFI_PLUGIN_EXPORT int zd_shm_provider_alloc_gc_defrag_blocking(
    z_buf_layout_alloc_result_t* result,
    const z_loaned_shm_provider_t* provider,
    size_t size);

// Check allocation status from result
// Returns: ZC_BUF_LAYOUT_ALLOC_STATUS_OK (0), _ALLOC_ERROR (1), _LAYOUT_ERROR (2)
FFI_PLUGIN_EXPORT int zd_buf_alloc_status(const z_buf_layout_alloc_result_t* result);

// Extract the mutable buffer from a successful allocation result
FFI_PLUGIN_EXPORT void zd_alloc_result_buf_move(
    z_owned_shm_mut_t* buf,
    z_buf_layout_alloc_result_t* result);
```

### SHM Buffer Operations

```c
// Get mutable data pointer for writing into SHM buffer
FFI_PLUGIN_EXPORT uint8_t* zd_shm_mut_data_mut(z_loaned_shm_mut_t* buf);

// Get length of SHM buffer
FFI_PLUGIN_EXPORT size_t zd_shm_mut_len(const z_loaned_shm_mut_t* buf);

// Get a loaned mutable reference
FFI_PLUGIN_EXPORT z_loaned_shm_mut_t* zd_shm_mut_loan_mut(z_owned_shm_mut_t* buf);

// Convert mutable SHM buffer → immutable SHM buffer (consumes mutable)
FFI_PLUGIN_EXPORT void zd_shm_from_mut(z_owned_shm_t* shm, z_owned_shm_mut_t* buf);

// Convert immutable SHM → bytes for publishing (consumes SHM, zero-copy)
FFI_PLUGIN_EXPORT void zd_bytes_from_shm(z_owned_bytes_t* bytes, z_owned_shm_t* shm);

// Shortcut: convert mutable SHM → bytes directly (consumes mutable, zero-copy)
FFI_PLUGIN_EXPORT void zd_bytes_from_shm_mut(z_owned_bytes_t* bytes, z_owned_shm_mut_t* buf);

// Drop owned SHM buffers
FFI_PLUGIN_EXPORT void zd_shm_drop(z_owned_shm_t* shm);
FFI_PLUGIN_EXPORT void zd_shm_mut_drop(z_owned_shm_mut_t* buf);
```

### SHM Detection on Receive Side

```c
// Check if bytes payload is backed by SHM (immutable).
// Returns 0 (Z_OK) if SHM-backed, sets *shm to the loaned SHM reference.
// Returns negative if not SHM.
FFI_PLUGIN_EXPORT int zd_bytes_as_loaned_shm(
    const z_loaned_bytes_t* bytes,
    const z_loaned_shm_t** shm);

// Check if bytes payload has mutable SHM access.
// Returns 0 if mutable SHM, sets *shm_mut.
// Returns negative if immutable or not SHM.
FFI_PLUGIN_EXPORT int zd_bytes_as_mut_loaned_shm(
    z_loaned_bytes_t* bytes,
    z_loaned_shm_mut_t** shm_mut);

// Try to get mutable access to an immutable SHM buffer.
// Succeeds only if this process is the sole reference holder.
// Returns 0 if successful, negative otherwise.
FFI_PLUGIN_EXPORT int zd_shm_try_reloan_mut(
    z_loaned_shm_t* shm,
    z_loaned_shm_mut_t** shm_mut);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function |
|----------------|-----------------|
| `zd_shm_provider_default_new` | `z_shm_provider_default_new` |
| `zd_shm_provider_loan` | `z_shm_provider_loan` (macro) |
| `zd_shm_provider_drop` | `z_shm_provider_drop` (macro) |
| `zd_shm_provider_alloc` | `z_shm_provider_alloc` |
| `zd_shm_provider_alloc_gc_defrag_blocking` | `z_shm_provider_alloc_gc_defrag_blocking` |
| `zd_buf_alloc_status` | Direct field access on `z_buf_layout_alloc_result_t.status` |
| `zd_alloc_result_buf_move` | `z_shm_mut_move` on `result.buf` |
| `zd_shm_mut_data_mut` | `z_shm_mut_data_mut` |
| `zd_shm_mut_len` | `z_shm_mut_len` |
| `zd_shm_mut_loan_mut` | `z_shm_mut_loan_mut` (macro) |
| `zd_shm_from_mut` | `z_shm_from_mut` + `z_shm_mut_move` |
| `zd_bytes_from_shm` | `z_bytes_from_shm` + `z_shm_move` |
| `zd_bytes_from_shm_mut` | `z_bytes_from_shm_mut` + `z_shm_mut_move` |
| `zd_shm_drop` | `z_shm_drop` (macro) |
| `zd_shm_mut_drop` | `z_shm_mut_drop` (macro) |
| `zd_bytes_as_loaned_shm` | `z_bytes_as_loaned_shm` |
| `zd_bytes_as_mut_loaned_shm` | `z_bytes_as_mut_loaned_shm` |
| `zd_shm_try_reloan_mut` | `z_shm_try_reloan_mut` |

## Dart API Surface

### New file: `packages/zenoh/lib/src/shm_provider.dart`

```dart
/// Manages a POSIX shared memory pool for zero-copy data transfer.
class ShmProvider {
  /// Create a SHM provider with the given total pool size in bytes.
  ShmProvider({required int size});

  /// Allocate a mutable SHM buffer (simple allocation, may fail).
  ShmMutBuffer alloc(int size);

  /// Allocate with GC, defragmentation, and blocking (safest).
  ShmMutBuffer allocGcDefragBlocking(int size);

  /// Release the provider and its memory pool.
  void close();
}
```

### New file: `packages/zenoh/lib/src/shm_buffer.dart`

```dart
/// A mutable shared memory buffer — writable via raw pointer access.
class ShmMutBuffer {
  /// Raw pointer to the buffer data for zero-copy writes.
  /// Use with Pointer<Uint8>.asTypedList(length) to get a writable Uint8List view.
  Pointer<Uint8> get data;

  /// Length of the buffer in bytes.
  int get length;

  /// Convert to bytes for publishing (consumes this buffer, zero-copy).
  ZBytes toBytes();

  /// Convert to an immutable SHM buffer (consumes this mutable buffer).
  ShmBuffer toImmutable();

  /// Drop (free) without converting.
  void dispose();
}

/// An immutable shared memory buffer — read-only.
class ShmBuffer {
  /// Convert to bytes for publishing (consumes this buffer, zero-copy).
  ZBytes toBytes();

  /// Drop (free) without converting.
  void dispose();
}
```

### Modify `packages/zenoh/lib/src/bytes.dart`

Add SHM detection to `ZBytes`:

```dart
class ZBytes {
  // ... existing methods ...

  /// Check if this payload is backed by shared memory.
  bool get isShmBacked;

  /// Attempt to get mutable SHM access to this payload.
  /// Returns null if not SHM-backed or if mutable access is not available.
  ShmMutBuffer? asShmMut();
}
```

### Modify `packages/zenoh/lib/zenoh.dart`

Add exports for `ShmProvider`, `ShmMutBuffer`, `ShmBuffer`.

## CLI Examples to Create

### `packages/zenoh/bin/z_pub_shm.dart`

Mirrors `extern/zenoh-c/examples/z_pub_shm.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_pub_shm.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>    (default: 'demo/example/zenoh-dart-pub')
    -p, --payload <VALUE>  (default: 'Pub from Dart (SHM)!')
```

Behavior:
1. Open session
2. Declare publisher
3. Create SHM provider (pool size: 4096)
4. Loop:
   a. Allocate SHM buffer (GC+defrag+blocking)
   b. Write payload string into buffer via raw pointer
   c. Convert buffer to bytes (zero-copy)
   d. Publish
   e. Sleep 1 second
5. Clean up

### `packages/zenoh/bin/z_sub_shm.dart`

Mirrors `extern/zenoh-c/examples/z_sub_shm.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_sub_shm.dart [OPTIONS]

Options:
    -k, --key <KEYEXPR>  (default: 'demo/example/**')
```

Behavior:
1. Open session
2. Declare subscriber
3. For each received sample:
   a. Check if payload is SHM-backed
   b. If SHM: try mutable access → print "SHM (MUT)" or "SHM (IMMUT)"
   c. If not SHM: print "RAW"
   d. Print keyexpr, payload, kind
4. Run until SIGINT

## SHM Publish Workflow in Dart

```dart
final provider = ShmProvider(size: 4096);
final buf = provider.allocGcDefragBlocking(256);

// Write directly to shared memory (zero-copy):
final data = utf8.encode('[${idx}] Pub from Dart (SHM)!');
buf.data.asTypedList(data.length).setAll(0, data);

// Convert to bytes and publish (zero-copy, consumes buf):
final payload = buf.toBytes();
publisher.putBytes(payload);
```

## SHM Receive Detection in Dart

```dart
subscriber.stream.listen((sample) {
  if (sample.payload.isShmBacked) {
    final mutBuf = sample.payload.asShmMut();
    if (mutBuf != null) {
      print('SHM (MUT)');
      mutBuf.dispose();
    } else {
      print('SHM (IMMUT)');
    }
  } else {
    print('RAW');
  }
  print('${sample.kind}: ${sample.keyExpr} => ${sample.payload}');
});
```

## Verification

1. `cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `fvm dart analyze packages/zenoh` — no errors
3. **Unit test**: Create SHM provider, allocate buffer, write data, read back, verify
4. **Unit test**: Allocate, convert to bytes, check `isShmBacked` returns true
5. **Unit test**: Create `ZBytes.fromString()`, check `isShmBacked` returns false
6. **Integration test**: Run `packages/zenoh/bin/z_sub_shm.dart` + `packages/zenoh/bin/z_pub_shm.dart` — subscriber detects SHM
7. **Integration test**: Run `packages/zenoh/bin/z_sub_shm.dart` + `packages/zenoh/bin/z_put.dart` — subscriber detects RAW
8. **Unit test**: Provider alloc with insufficient pool size handles error correctly
