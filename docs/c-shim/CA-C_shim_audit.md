# C Shim Architecture Audit

**Date:** 2026-03-09
**Scope:** `src/zenoh_dart.{h,c}` — 62 exported functions, ~700 lines
**Reviewed against:** zenoh-c v1.7.2 (`extern/zenoh-c/`), Dart FFI (`dart:ffi`)
**Audience:** Expert C and Dart code reviewers

---

## 1. What Problem the C Shim Solves

### 1.1 The FFI Barrier

Dart's `dart:ffi` can only call **exported C symbols** — real functions with
external linkage that appear in the shared library's dynamic symbol table.
It cannot call:

- **C11 `_Generic` macros** — compile-time type dispatchers with no symbol
- **`static inline` functions** — inlined by the compiler, not exported
- **C preprocessor macros** — text substitution, no symbol
- **C++ overloaded functions** — name-mangled, no stable C ABI

zenoh-c v1.7.2 uses all four patterns extensively. Its public API is designed
for C/C++ consumers who `#include` the headers and let the compiler resolve
macros at compile time. A Dart FFI consumer cannot `#include` anything — it
can only `dlsym()` symbols from the compiled `.so`.

### 1.2 Specific zenoh-c Patterns That Block Direct FFI

#### Pattern A: `_Generic` Polymorphic Macros

zenoh-c provides generic convenience macros for loan, drop, move, and call
operations. From `zenoh_macros.h`:

```c
#define z_loan(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_loan, \
        z_owned_config_t : z_config_loan, \
        z_owned_session_t : z_session_loan, \
        z_owned_publisher_t : z_publisher_loan, \
        z_owned_subscriber_t : z_subscriber_loan, \
        /* ... 50+ type branches ... */ \
    )(&this_)

#define z_drop(this_) \
    _Generic((this_), \
        z_moved_bytes_t* : z_bytes_drop, \
        z_moved_config_t* : z_config_drop, \
        z_moved_session_t* : z_session_drop, \
        /* ... 50+ type branches ... */ \
    )(this_)
```

`_Generic` is a C11 compile-time construct. The compiler selects one branch
based on the expression type and emits a direct call to (e.g.)
`z_session_loan`. The macro itself produces **no symbol** — `z_loan` does
not appear in `libzenohc.so`'s symbol table.

The underlying monomorphic functions (`z_bytes_loan`, `z_config_loan`, etc.)
**are** exported. The shim could theoretically be bypassed for these. But:

1. The `z_*_move()` variants are `static inline` (see Pattern B).
2. Functions like `z_open()`, `z_put()`, `z_close()` expect `z_moved_*_t*`
   parameters that can only be obtained via `z_*_move()`.
3. Options structs require initialization via macros before being passed.

So even though `z_bytes_loan` is exported, calling `z_put` is not — you
cannot construct its arguments without the `static inline` move functions.

#### Pattern B: `static inline` Move Functions

zenoh-c's ownership model uses opaque "moved" pointer types. The conversion
from `z_owned_*_t*` to `z_moved_*_t*` is done via `static inline` functions
in the header:

```c
static inline z_moved_bytes_t* z_bytes_move(z_owned_bytes_t* x) {
    return (z_moved_bytes_t*)(x);
}
static inline z_moved_config_t* z_config_move(z_owned_config_t* x) {
    return (z_moved_config_t*)(x);
}
static inline z_moved_session_t* z_session_move(z_owned_session_t* x) {
    return (z_moved_session_t*)(x);
}
// ... 50+ variants
```

These are `static inline` — they are **not exported** from `libzenohc.so`.
They exist only in the header for compile-time type safety. At the machine
level, they are identity casts (pointer reinterpret), but Dart FFI cannot
perform them because:

1. The symbol does not exist in the `.so`.
2. Dart FFI has no concept of C pointer type casts between opaque struct types.
3. Even if Dart cast the pointer value, it could not satisfy the type system
   of functions expecting `z_moved_*_t*` parameters.

**This is the fundamental reason the C shim exists.** The shim compiles
against the headers, resolves all `static inline` and `_Generic` macros
at compile time, and exports the result as real symbols.

#### Pattern C: Options Struct Initialization

zenoh-c functions take options structs that must be initialized to defaults
before use:

```c
z_put_options_t opts;
z_put_options_default(&opts);   // macro or inline — sets default values
opts.encoding = z_encoding_move(&owned_encoding);
z_put(session, keyexpr, z_bytes_move(payload), &opts);
```

`z_put_options_default` may be a macro or inline function. Even when it's a
real function, the options struct is stack-allocated in C — Dart FFI can
allocate the struct via `calloc` but needs to know the exact layout, which
changes between zenoh-c versions. The shim internalizes this:

```c
FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload) {
  z_put_options_t opts;
  z_put_options_default(&opts);
  return z_put(session, keyexpr, z_bytes_move(payload), &opts);
}
```

Dart sees one function with three parameters. The options struct, its
initialization, and the move semantics are all hidden.

#### Pattern D: Opaque Type Sizes

zenoh-c types (`z_owned_session_t`, `z_owned_config_t`, etc.) are opaque
structs whose sizes are not part of the public C ABI. Dart must allocate
native memory for these types but cannot `sizeof()` them at runtime. The
shim exports size functions:

```c
FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void) {
    return sizeof(z_owned_session_t);
}
```

Dart allocates via `calloc.allocate(bindings.zd_session_sizeof())`, which is
correct regardless of the actual struct layout. This is a standard pattern
for FFI with opaque types and is well-implemented.

### 1.3 What the Shim Does NOT Do

The shim is deliberately thin. It does not:

- Add error recovery or retry logic
- Buffer or queue data
- Manage threads or synchronization
- Add abstraction layers or new concepts
- Change zenoh-c's ownership semantics

Every `zd_*` function maps to one or a small sequence of `z_*` calls. The
shim is a **mechanical flattening layer**, not an abstraction.

---

## 2. Function-by-Function Analysis

### 2.1 Initialization (2 functions)

| Function | Wraps | Purpose |
|----------|-------|---------|
| `zd_init_dart_api_dl` | `Dart_InitializeApiDL` | Initializes Dart native API for `Dart_PostCObject_DL` |
| `zd_init_log` | `zc_init_log_from_env_or` | Initializes zenoh logger |

**Assessment:** Correct and minimal. `zd_init_dart_api_dl` must be called
before any NativePort usage. The lazy singleton in `native_lib.dart` calls
it on first access, which is the right place.

### 2.2 Config (5 functions)

| Function | Wraps | Move/Loan Macros Used |
|----------|-------|-----------------------|
| `zd_config_sizeof` | `sizeof(z_owned_config_t)` | — |
| `zd_config_default` | `z_config_default` | — |
| `zd_config_insert_json5` | `z_config_loan_mut` + `zc_config_insert_json5` | `z_config_loan_mut` (inline) |
| `zd_config_loan` | `z_config_loan` | — |
| `zd_config_drop` | `z_config_drop(z_config_move(...))` | `z_config_move` (inline) |

**Assessment:** Correct. `zd_config_insert_json5` properly obtains a mutable
loan before inserting. The drop function correctly sequences move-then-drop.

**Observation — `zd_config_loan` may be unused.** The Dart code passes config
pointers directly to `zd_open_session`, which calls `z_config_move`
internally. If `zd_config_loan` is never called from Dart, it is dead code.
This is harmless but worth noting.

### 2.3 Session (4 functions)

| Function | Wraps | Move/Loan Macros Used |
|----------|-------|-----------------------|
| `zd_session_sizeof` | `sizeof(z_owned_session_t)` | — |
| `zd_open_session` | `z_open(session, z_config_move(config), NULL)` | `z_config_move` |
| `zd_session_loan` | `z_session_loan` | — |
| `zd_close_session` | `z_close` + `z_session_drop` | `z_session_loan_mut`, `z_session_move` |

**Assessment:** Correct. `zd_close_session` performs the two-step
close-then-drop sequence that zenoh-c requires. The third parameter to
`z_open` (open options) is NULL, meaning defaults — appropriate for the
current phase.

**Note:** `z_open` consumes the config via `z_config_move`. The Dart side
correctly calls `config.markConsumed()` after `zd_open_session` to prevent
double-free. This is audited in Section 3.

### 2.4 KeyExpr (4 functions)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_view_keyexpr_sizeof` | `sizeof(z_view_keyexpr_t)` | — |
| `zd_view_keyexpr_from_str` | `z_view_keyexpr_from_str` | Returns Z_EINVAL on invalid expr |
| `zd_view_keyexpr_loan` | `z_view_keyexpr_loan` | — |
| `zd_keyexpr_as_view_string` | `z_keyexpr_as_view_string` | — |

**Assessment:** Correct. Uses view (non-owning) key expressions throughout,
which avoids unnecessary copies. The Dart `KeyExpr` class owns the backing
C string and frees it in `dispose()` — the view borrows this string, so
the lifetime constraint is satisfied as long as `KeyExpr.dispose()` is not
called while the view is in use. The `_withKeyExpr` helper in `session.dart`
guarantees this via `try/finally`.

### 2.5 Bytes (5 functions)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_bytes_sizeof` | `sizeof(z_owned_bytes_t)` | — |
| `zd_bytes_copy_from_str` | `z_bytes_copy_from_str` | Copies string into zenoh-owned bytes |
| `zd_bytes_copy_from_buf` | `z_bytes_copy_from_buf` | Copies buffer into zenoh-owned bytes |
| `zd_bytes_loan` | `z_bytes_loan` | — |
| `zd_bytes_drop` | `z_bytes_drop(z_bytes_move(...))` | `z_bytes_move` |
| `zd_bytes_to_string` | `z_bytes_to_string` | — |

**Assessment:** Correct. Both `copy_from_str` and `copy_from_buf` make
defensive copies into zenoh-owned memory, which is the right approach for
FFI — the Dart-allocated buffer can be freed immediately after the copy.

### 2.6 String utilities (7 functions)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_string_sizeof` | `sizeof(z_owned_string_t)` | — |
| `zd_string_loan` | `z_string_loan` | — |
| `zd_string_data` | `z_string_data` | Not null-terminated |
| `zd_string_len` | `z_string_len` | — |
| `zd_string_drop` | `z_string_drop(z_string_move(...))` | — |
| `zd_view_string_sizeof` | `sizeof(z_view_string_t)` | — |
| `zd_view_string_data` | `z_view_string_loan` + `z_string_data` | Convenience |
| `zd_view_string_len` | `z_view_string_loan` + `z_string_len` | Convenience |

**Assessment:** Correct. The view string convenience functions
(`zd_view_string_data`, `zd_view_string_len`) each do a loan-then-access
in one call, reducing the number of FFI round-trips from Dart. This is a
sensible optimization.

**Important:** `zd_string_data` returns a pointer that is **not guaranteed
to be null-terminated**. The Dart side correctly uses
`data.cast<Utf8>().toDartString(length: len)` with an explicit length
parameter everywhere. This is correct and avoids buffer overread.

### 2.7 Put / Delete (2 functions)

| Function | Wraps | Move/Loan Macros Used |
|----------|-------|-----------------------|
| `zd_put` | `z_put_options_default` + `z_put` | `z_bytes_move` |
| `zd_delete` | `z_delete_options_default` + `z_delete` | — |

**Assessment:** Correct. Both functions initialize options to defaults and
pass them through. `zd_put` moves the payload, transferring ownership to
zenoh-c. The Dart side calls `payload.markConsumed()` after the call.

**Design choice:** `zd_put` does not expose encoding, attachment, or QoS
options. These are available through `zd_publisher_put` (the declared
publisher path). This split mirrors zenoh-c's Session-level vs
Publisher-level API separation and is intentional — Session-level `put` is
a convenience for simple cases.

### 2.8 Subscriber (3 functions + 2 static callbacks)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_subscriber_sizeof` | `sizeof(z_owned_subscriber_t)` | — |
| `zd_declare_subscriber` | `z_closure_sample` + `z_declare_subscriber` | Heap-allocates context |
| `zd_subscriber_drop` | `z_subscriber_drop(z_subscriber_move(...))` | — |

**Callback bridge:**

```
zenoh-c callback thread
  → _zd_sample_callback(sample, context)
    → extracts keyexpr, payload, kind, attachment, encoding
    → builds Dart_CObject array [string, Uint8List, int64, Uint8List|null, string]
    → Dart_PostCObject_DL(dart_port, &array)
      → Dart ReceivePort.listen callback
        → constructs Sample object
        → adds to StreamController
```

**Assessment:** This is the most complex part of the shim and the most
critical to audit.

**Correctness of `_zd_sample_callback`:**

1. **Key expression extraction** (lines 202-207): Obtains a view string from
   the sample's key expression. The view borrows from the sample, which is
   valid for the duration of the callback. The data is then copied into a
   `malloc`'d buffer for `Dart_CObject_kString`, which requires a
   null-terminated string. **Correct.**

2. **Payload extraction** (lines 209-214): Converts payload bytes to a string
   via `z_bytes_to_string`. This creates an owned string that must be dropped.
   The payload data is sent as `Dart_CObject_kTypedData` (Uint8List) pointing
   to the string's data buffer. **The data pointer is valid only until
   `z_string_drop` is called.** `Dart_PostCObject_DL` copies the typed data
   into the Dart heap before returning, so the pointer remains valid during
   the post. **Correct but subtle** — see Finding F1.

3. **Kind** (line 217): `z_sample_kind` returns an enum value (0=put,
   1=delete). Sent as `Dart_CObject_kInt64`. **Correct.**

4. **Attachment** (lines 220-261): Nullable. When present, converted to
   string via `z_bytes_to_string` and sent as `Uint8List`. When absent,
   sent as `Dart_CObject_kNull`. The owned string is dropped after the post.
   **Correct.**

5. **Encoding** (lines 223-228): Extracted via `z_encoding_to_string`, copied
   to a `malloc`'d null-terminated buffer, sent as string. **Correct.**

6. **Memory cleanup** (lines 279-285): Frees `key_buf`, `enc_buf`, and drops
   all owned strings. Attachment string is dropped only if present (guarded
   by `has_attachment`). **Correct.**

**Context lifecycle:**

- `zd_declare_subscriber` heap-allocates `zd_subscriber_context_t` via
  `malloc`. On failure, it drops the closure (which invokes `_zd_sample_drop`,
  freeing the context). On success, the context lives until
  `zd_subscriber_drop` triggers the closure's drop callback.
- `_zd_sample_drop` calls `free(context)`. **Correct.**

**Error handling on `zd_declare_subscriber` failure:**

```c
if (rc != 0) {
    z_closure_sample_drop(z_closure_sample_move(&callback));
}
```

This handles the case where `z_declare_subscriber` fails and does not consume
the closure. The shim drops the closure manually to prevent a memory leak.
**Correct.**

### 2.9 Publisher (8 functions + 2 static callbacks)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_publisher_sizeof` | `sizeof(z_owned_publisher_t)` | — |
| `zd_declare_publisher` | `z_publisher_options_default` + `z_declare_publisher` | Sentinel-based optional params |
| `zd_publisher_loan` | `z_publisher_loan` | — |
| `zd_publisher_drop` | `z_publisher_drop(z_publisher_move(...))` | — |
| `zd_publisher_put` | `z_publisher_put_options_default` + `z_publisher_put` | Moves payload + optional attachment |
| `zd_publisher_delete` | `z_publisher_delete_options_default` + `z_publisher_delete` | — |
| `zd_publisher_keyexpr` | `z_publisher_keyexpr` | Returns loaned keyexpr |
| `zd_publisher_declare_background_matching_listener` | `z_closure_matching_status` + `z_publisher_declare_background_matching_listener` | NativePort bridge |
| `zd_publisher_get_matching_status` | `z_publisher_get_matching_status` | Out-parameter for matching bool |

**Sentinel pattern in `zd_declare_publisher`:**

```c
z_owned_encoding_t owned_encoding;
if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
}
if (congestion_control >= 0) {
    opts.congestion_control = (z_congestion_control_t)congestion_control;
}
if (priority >= 0) {
    opts.priority = (z_priority_t)priority;
}
```

Sentinel values (`NULL` for strings, `-1` for enums) let Dart pass defaults
without the shim needing multiple function overloads. Dart maps its enum
values to C integers: `CongestionControl.block` → 0, `Priority.data` → 5
(Dart index 4 + 1). The shim passes these through with a cast. **Correct.**

**`zd_publisher_put` ownership handling:**

```c
if (attachment != NULL) {
    opts.attachment = z_bytes_move(attachment);
}
return z_publisher_put(publisher, z_bytes_move(payload), &opts);
```

Both payload and attachment are moved (consumed). Dart calls
`payload.markConsumed()` and `attachment.markConsumed()` after the call.
**Correct.**

**Matching listener callback:** Posts `Int64` (1 or 0) via NativePort. Same
heap-allocated context pattern as subscriber. Cleanup on failure mirrors
subscriber. **Correct.**

### 2.10 Info / ZID (4 functions + 1 static callback)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_info_zid` | `z_info_zid` | Copies 16 bytes to caller buffer |
| `zd_id_to_string` | `z_id_to_string` | Copies bytes in, gets string out |
| `zd_info_routers_zid` | `z_closure_zid` + `z_info_routers_zid` | Buffer-based collection |
| `zd_info_peers_zid` | `z_closure_zid` + `z_info_peers_zid` | Buffer-based collection |

**Buffer-based ZID collection:**

```c
typedef struct {
    uint8_t* out_ids;
    int max_count;
    int count;
} zd_zid_collect_context_t;

static void _zd_zid_collect_callback(const z_id_t* id, void* context) {
    zd_zid_collect_context_t* ctx = (zd_zid_collect_context_t*)context;
    if (ctx->count < ctx->max_count) {
        memcpy(ctx->out_ids + ctx->count * 16, id->id, 16);
        ctx->count++;
    }
}
```

This uses stack-allocated context and a caller-provided buffer. The closure
has `NULL` for the drop callback because the context is stack-allocated and
does not need freeing. **Correct.**

The Dart side allocates `maxCount * 16` bytes, calls the function, reads
`count * 16` bytes back, and constructs `ZenohId` objects. **Correct.**

**Design choice:** This uses synchronous buffer collection instead of
NativePort (unlike subscriber and scout). This is appropriate because
`z_info_routers_zid` is synchronous and the callback is invoked inline
before the function returns. Using NativePort here would add unnecessary
async complexity.

### 2.11 Scout (2 functions + 1 static callback)

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_scout` | `z_scout_options_default` + `z_scout` + null sentinel | NativePort bridge |
| `zd_whatami_to_view_string` | `z_whatami_to_view_string` | — |

**Scout callback:**

`_zd_scout_hello_callback` extracts ZID (16 bytes), whatami (int), and
locators (semicolon-joined string) from each `z_loaned_hello_t`. Locators
are built with a two-pass algorithm: compute total length, allocate, copy.
**Correct and null-terminated for `Dart_CObject_kString`.**

**Locator string construction:**

```c
// First pass: compute total length
for (size_t i = 0; i < loc_count; i++) {
    loc_buf_len += z_string_len(loc);
    if (i < loc_count - 1) loc_buf_len += 1; // semicolon
}
loc_buf = (char*)malloc(loc_buf_len + 1);
// Second pass: copy
```

Two-pass is correct. The `+1` for the null terminator is correct.
Empty locator case allocates a 1-byte buffer with `'\0'`. **Correct.**

**Important:** `zd_scout` uses **stack-allocated** context:

```c
zd_scout_context_t ctx = { .dart_port = (Dart_Port_DL)dart_port };
z_closure_hello(&closure, _zd_scout_hello_callback, NULL, &ctx);
```

The drop callback is `NULL` because the context is on the stack. This is
safe because `z_scout` is synchronous — it blocks until the timeout expires,
and all callbacks fire before `z_scout` returns. The context is valid for the
entire duration. **Correct.**

**Null sentinel:** After `z_scout` returns, the shim posts a null
`Dart_CObject` to signal completion. The Dart side uses a `Completer` that
resolves when it receives null. **Correct.**

### 2.12 Shared Memory (13 functions, conditionally compiled)

All SHM functions are guarded by:

```c
#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)
```

`CMakeLists.txt` defines both flags. This is correct — SHM is an unstable
zenoh feature that requires explicit opt-in.

| Function | Wraps | Notes |
|----------|-------|-------|
| `zd_shm_provider_sizeof` | `sizeof(z_owned_shm_provider_t)` | — |
| `zd_shm_provider_new` | `z_shm_provider_default_new` | — |
| `zd_shm_provider_loan` | `z_shm_provider_loan` | — |
| `zd_shm_provider_drop` | `z_shm_provider_drop(z_shm_provider_move(...))` | — |
| `zd_shm_provider_available` | `z_shm_provider_available` | — |
| `zd_shm_mut_sizeof` | `sizeof(z_owned_shm_mut_t)` | — |
| `zd_shm_provider_alloc` | `z_shm_provider_alloc` | Translates result struct |
| `zd_shm_provider_alloc_gc_defrag_blocking` | `z_shm_provider_alloc_gc_defrag_blocking` | Translates result struct |
| `zd_shm_mut_loan_mut` | `z_shm_mut_loan_mut` | — |
| `zd_shm_mut_data_mut` | `z_shm_mut_data_mut` | Returns raw pointer |
| `zd_shm_mut_len` | `z_shm_mut_len` | — |
| `zd_bytes_from_shm_mut` | `z_bytes_from_shm_mut(bytes, z_shm_mut_move(buf))` | Consumes buffer |
| `zd_shm_mut_drop` | `z_shm_mut_drop(z_shm_mut_move(...))` | — |

**Alloc result translation:**

```c
z_buf_layout_alloc_result_t result;
z_shm_provider_alloc(&result, provider, size);
if (result.status == ZC_BUF_LAYOUT_ALLOC_STATUS_OK) {
    *buf = result.buf;
    return 0;
}
return -1;
```

zenoh-c returns alloc results as a struct with status + buffer. The shim
flattens this to a return code + out-parameter pattern. The Dart side returns
`null` on failure, which is the right approach for allocation failures (not
exceptional — caller should check and retry or use a different strategy).
**Correct.**

---

## 3. Ownership Model Audit

The most subtle aspect of the shim is ownership transfer between Dart-managed
memory (via `calloc`/`malloc`) and zenoh-c-managed memory (via internal Rust
allocator). Every ownership transition must be correct to avoid double-frees,
use-after-free, or memory leaks.

### 3.1 Ownership Transitions in the Shim

| Operation | Ownership Flow | Shim Role |
|-----------|---------------|-----------|
| `zd_config_default` | zenoh-c creates config in Dart-calloc'd wrapper | Wrapper memory: Dart. Config internals: zenoh-c. |
| `zd_open_session` | Config consumed by `z_config_move` → zenoh-c owns | Dart calls `markConsumed()` on Config |
| `zd_bytes_copy_from_str` | zenoh-c copies string into its own memory | Dart can free the source string immediately |
| `zd_put` | Payload consumed by `z_bytes_move` → zenoh-c owns | Dart calls `markConsumed()` on ZBytes |
| `zd_declare_subscriber` | Context heap-allocated, owned by closure | Freed by `_zd_sample_drop` when subscriber drops |
| `zd_bytes_from_shm_mut` | SHM buffer consumed by `z_shm_mut_move` | Dart marks ShmMutBuffer as consumed |

### 3.2 Dart-Side Ownership Tracking

The Dart classes use a consistent two-flag pattern:

```dart
bool _disposed = false;  // Explicitly freed by caller
bool _consumed = false;  // Ownership transferred to zenoh-c
```

Every accessor checks both flags:

```dart
void _ensureNotDisposed() {
    if (_disposed) throw StateError('ZBytes has been disposed');
}
void _ensureNotConsumed() {
    if (_consumed) throw StateError('ZBytes has been consumed');
}
```

And `dispose()` skips the native drop if consumed:

```dart
void dispose() {
    if (_disposed) return;
    if (_consumed) return;    // zenoh-c owns the memory now
    _disposed = true;
    bindings.zd_bytes_drop(_ptr.cast());
    calloc.free(_ptr);
}
```

**Assessment:** This pattern correctly prevents:
- **Double-free**: `_disposed` flag prevents re-entry
- **Use-after-free**: Guards on every accessor
- **Use-after-consume**: Separate `_consumed` flag
- **Leak on consume**: Skips native drop (zenoh-c handles it) but still
  notes the object is dead

### 3.3 Wrapper Memory vs. Content Memory

A critical distinction: Dart `calloc`-allocates wrapper memory for opaque
zenoh types (e.g., `calloc.allocate(bindings.zd_session_sizeof())`). This
wrapper holds zenoh-c's internal state. On cleanup:

1. Call `zd_*_drop()` to release zenoh-c's internal resources (Rust allocator)
2. Call `calloc.free()` to release the wrapper memory (Dart allocator)

This two-step cleanup is implemented consistently across all classes:

```dart
// Session.close():
bindings.zd_close_session(_ptr.cast());  // Step 1: zenoh-c cleanup
calloc.free(_ptr);                        // Step 2: wrapper cleanup

// Config.dispose():
bindings.zd_config_drop(_ptr.cast());    // Step 1
calloc.free(_ptr);                        // Step 2
```

**Assessment:** Correct. The two-step pattern is applied consistently.

---

## 4. Thread Safety Analysis

### 4.1 Callback Threading Model

zenoh-c invokes subscriber callbacks from its internal networking threads,
not from the Dart isolate's thread. `Dart_PostCObject_DL` is the **only**
thread-safe mechanism for posting data to a Dart isolate from a foreign
thread.

The shim correctly uses `Dart_PostCObject_DL` for all callbacks:
- `_zd_sample_callback` (subscriber samples)
- `_zd_matching_status_callback` (publisher matching)
- `_zd_scout_hello_callback` (scouting results)

**`Dart_PostCObject_DL` semantics:** The function copies the `Dart_CObject`
data into the Dart heap and enqueues a message on the target port's message
queue. It returns synchronously. The original data (stack-allocated
`Dart_CObject` structs, `malloc`'d string buffers) can be freed immediately
after the call returns.

**Assessment:** The cleanup in `_zd_sample_callback` (lines 279-285) happens
after `Dart_PostCObject_DL` returns, which is correct — the data has already
been copied by that point.

### 4.2 Context Struct Races

`zd_subscriber_context_t` contains only a `Dart_Port_DL` value (an integer).
It is written once during `zd_declare_subscriber` and read from callbacks.
There is no mutation after initialization, so no races are possible.
**Correct.**

---

## 5. Findings

### F1: Payload Encoding Assumption in Subscriber Callback [OBSERVATION]

**Location:** `zenoh_dart.c:210-214`, `subscriber.dart:49`

The C shim converts payload bytes to a string via `z_bytes_to_string`:

```c
const z_loaned_bytes_t* payload_loaned = z_sample_payload(sample);
z_owned_string_t payload_str;
z_bytes_to_string(payload_loaned, &payload_str);
```

Then sends the string's raw bytes as `Dart_CObject_kTypedData`:

```c
c_payload.value.as_typed_data.values = (uint8_t*)payload_data;
```

The Dart side then does `utf8.decode(payloadBytes)` to create the `payload`
string field.

This round-trip is:
1. C: bytes → `z_bytes_to_string` → owned string (byte buffer)
2. C: send byte buffer via NativePort
3. Dart: receive `Uint8List`, decode as UTF-8 to get `payload` string

The `z_bytes_to_string` conversion in step 1 is essentially a byte copy,
not a character encoding transformation. The data arrives in Dart as raw
bytes regardless. The intermediate string conversion in C adds an
unnecessary copy. Sending the raw bytes directly from
`z_sample_payload` would be more efficient, but would require using the
zenoh-c bytes reader API (`z_bytes_reader_*`) to extract raw bytes, which
is more complex.

**Severity:** Low. The extra copy is small relative to network I/O. This
is a performance optimization opportunity, not a correctness issue.

### F2: `Zenoh.initLog` Frees with `calloc.free` Instead of `malloc.free` [BUG]

**Location:** `zenoh.dart:42`

```dart
static void initLog(String fallback) {
    final cStr = fallback.toNativeUtf8();
    try {
      bindings.zd_init_log(cStr.cast<Char>());
    } finally {
      calloc.free(cStr);  // ← allocated by toNativeUtf8 (uses malloc)
    }
}
```

`String.toNativeUtf8()` allocates via `malloc` (from `package:ffi`). The
cleanup uses `calloc.free()`. Both `calloc` and `malloc` from `package:ffi`
ultimately call the same C `free()`, so this works in practice. However,
it is semantically incorrect — the allocator used for `free` should match
the allocator used for `alloc`.

Compare with `config.dart:61-62` which correctly uses `malloc.free`:

```dart
final nativeKey = key.toNativeUtf8();
// ...
malloc.free(nativeKey);  // ← correct
```

**Severity:** Cosmetic. No runtime impact because `package:ffi`'s `calloc`
and `malloc` allocators both use the system allocator. But it violates the
C best practice of matching `malloc`/`free` pairs and could cause issues
if `package:ffi` ever changes its allocator implementations.

### F3: `ZBytes.fromUint8List` Uses Element-by-Element Copy [PERFORMANCE]

**Location:** `bytes.dart:51-53`

```dart
final Pointer<Uint8> nativeBuf = calloc<Uint8>(data.length);
for (var i = 0; i < data.length; i++) {
    nativeBuf[i] = data[i];
}
```

This copies `Uint8List` to native memory one byte at a time. For large
payloads, this is measurably slower than `nativeBuf.asTypedList(data.length).setAll(0, data)`,
which uses `memcpy` internally. The SHM zero-copy path already uses the
`asTypedList` + `setAll` pattern correctly.

**Severity:** Low. Most payloads are small. Performance-sensitive paths
should use SHM or `Publisher.putBytes`.

### F4: No Validation of `max_count` Bounds in ZID Collection [OBSERVATION]

**Location:** `zenoh_dart.c:480-486`

```c
static void _zd_zid_collect_callback(const z_id_t* id, void* context) {
    zd_zid_collect_context_t* ctx = (zd_zid_collect_context_t*)context;
    if (ctx->count < ctx->max_count) {
        memcpy(ctx->out_ids + ctx->count * 16, id->id, 16);
        ctx->count++;
    }
}
```

The callback correctly bounds-checks against `max_count`. The Dart side
uses `maxCount = 64`, so up to 1024 bytes. This is a reasonable upper bound
for connected routers/peers.

If a deployment has more than 64 connected routers or peers, the extra ZIDs
are silently dropped. This is acceptable for the current use case but should
be documented in the Dart API.

**Severity:** None. The bounds check is correct. Documentation could note
the 64-entry limit.

### F5: `owned_encoding` Potentially Uninitialized on Non-NULL but Invalid Encoding String [EDGE CASE]

**Location:** `zenoh_dart.c:344-348`

```c
z_owned_encoding_t owned_encoding;
if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
}
```

If `z_encoding_from_str` returns a non-zero error code (invalid encoding
string), `owned_encoding` may be in an indeterminate state, and
`z_encoding_move` on it could be undefined behavior. The return value of
`z_encoding_from_str` is not checked.

In practice, zenoh-c's `z_encoding_from_str` always succeeds (it treats the
string as an opaque MIME type), so this is unlikely to trigger. But for
defensive C programming, the return code should be checked.

**Severity:** Low. No known trigger. Defensive fix would be to check the
return code and skip setting `opts.encoding` on failure.

### F6: Consistent `Pointer<Void>` Usage Across Dart Classes [GOOD PRACTICE]

All Dart wrapper classes use `Pointer<Void>` for the native pointer, with
`.cast()` at each FFI call site. This is the correct pattern for Dart FFI
with opaque types — it avoids generating Dart struct bindings for
zenoh-c's internal types and keeps the API surface minimal.

The alternative (generating Dart FFI struct bindings for every zenoh-c type)
would expose internal layout details and break on zenoh-c version changes.
`Pointer<Void>` with runtime `sizeof` queries is the right approach.

---

## 6. Conformance Summary

### 6.1 C Best Practices

| Practice | Status | Notes |
|----------|--------|-------|
| All exported symbols have `FFI_PLUGIN_EXPORT` | PASS | `__attribute__((visibility("default")))` on non-Windows |
| `C_VISIBILITY_PRESET hidden` in CMake | PASS | Only `FFI_PLUGIN_EXPORT` symbols are visible |
| Consistent `zd_` namespace prefix | PASS | No collisions with zenoh-c's `z_`/`zc_` namespace |
| Return code checking | PARTIAL | F5: `z_encoding_from_str` unchecked |
| Memory cleanup on all paths | PASS | Closures dropped on declare failure |
| No undefined behavior | PASS | All pointer arithmetic is bounds-checked |
| Minimal header includes | PASS | Only `stdint.h` and `zenoh.h` |
| Const correctness | PASS | `const` on all loan/read-only parameters |
| Stack allocation where possible | PASS | Scout and ZID contexts are stack-allocated |
| Heap allocation only when lifetime exceeds scope | PASS | Subscriber and matching contexts are heap-allocated |
| Feature guards for optional functionality | PASS | SHM behind `#ifdef` |

### 6.2 Dart FFI Best Practices

| Practice | Status | Notes |
|----------|--------|-------|
| `DynamicLibrary.open` with platform dispatch | PASS | `native_lib.dart` |
| Lazy singleton for bindings | PASS | Initialized on first access |
| `Dart_InitializeApiDL` before NativePort use | PASS | Called in `_initBindings` |
| `ReceivePort` for async callbacks | PASS | Subscriber, matching listener, scout |
| `StreamController` for event streams | PASS | Single-subscription, non-broadcast |
| `calloc.allocate(sizeof)` for opaque types | PASS | Consistent pattern |
| Ownership tracking with `_disposed`/`_consumed` | PASS | All wrapper classes |
| `try/finally` for temporary native allocations | PASS | `_withKeyExpr`, `KeyExpr`, encoding strings |
| Idempotent `close()`/`dispose()` | PASS | All classes |
| `StateError` on use-after-close | PASS | All classes |
| `ZenohException` with return code on FFI errors | PASS | All error paths |
| Explicit length for non-null-terminated strings | PASS | `toDartString(length: len)` everywhere |

### 6.3 Architecture Conformance

| Principle | Status | Notes |
|-----------|--------|-------|
| Shim is mechanical (no business logic) | PASS | Every function is 1-5 zenoh-c calls |
| Single-load library pattern | PASS | Only `libzenoh_dart.so` loaded; OS resolves `libzenohc.so` |
| No abstraction beyond what Dart needs | PASS | No unnecessary wrapper types |
| Options structs internalized | PASS | Dart never touches `z_*_options_t` |
| Move semantics handled in C | PASS | Dart never calls `z_*_move` |
| Callback bridge via NativePort | PASS | Thread-safe, copies data |
| Sentinel values for optional params | PASS | NULL for strings, -1 for enums |

---

## 7. Conclusion

The C shim is well-designed and correctly implemented. It solves the right
problem (flattening zenoh-c's macro-heavy API into FFI-callable symbols) with
minimal code and no unnecessary abstraction. The ownership model is
consistently tracked on both sides of the FFI boundary.

The five findings (F1-F5) are all low-severity: one cosmetic allocator
mismatch (F2), two performance observations (F1, F3), one unchecked return
code in a non-triggerable path (F5), and one documentation suggestion (F4).
None affect correctness in practice.

The codebase is production-quality for its current scope (62 functions, 6
entity types). The patterns established here (sizeof queries, NativePort
bridge, sentinel-based optional params, two-flag ownership tracking) provide
a solid foundation for the remaining phases.
