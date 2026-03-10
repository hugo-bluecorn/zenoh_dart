# C Shim Layer Audit: Existence Proof and Functional Analysis

**Scope:** `src/zenoh_dart.{h,c}` (62 exported symbols), the Dart FFI consumers in `packages/zenoh/lib/src/`, and the zenoh-c v1.7.2 headers that necessitate the shim.
**Audience:** Expert C and Dart code reviewers.
**Date:** 2026-03-09
**zenoh-c version:** v1.7.2

---

## Part A: Why the C Shim Must Exist

The zenoh-c v1.7.2 API relies on four patterns that Dart FFI cannot call. This section proves each pattern exists in the zenoh-c headers with exact file references, explains why Dart FFI cannot handle it with references to official Dart documentation, and shows how the C shim resolves each one.

---

### Pattern 1: C11 `_Generic` Macros and `static inline` Functions

#### 1.1 The Problem in zenoh-c

The zenoh-c public API uses C11 `_Generic` selection macros as its primary entry points for drop, move, loan, and closure construction. These macros dispatch to type-specific functions at compile time based on the argument's C type.

**Evidence** (`extern/zenoh-c/include/zenoh_macros.h`):

The `z_drop()` macro (lines 150-208) dispatches to 40+ type-specific drop functions:

```c
// zenoh_macros.h:150-208
#define z_drop(this_) \
    _Generic((this_), \
        z_moved_bytes_t* : z_bytes_drop, \
        z_moved_config_t* : z_config_drop, \
        z_moved_session_t* : z_session_drop, \
        z_moved_publisher_t* : z_publisher_drop, \
        z_moved_subscriber_t* : z_subscriber_drop, \
        z_moved_shm_mut_t* : z_shm_mut_drop, \
        z_moved_shm_provider_t* : z_shm_provider_drop, \
        /* ... 33 more type cases ... */ \
    )(this_)
```

The `z_loan()` macro (lines 65-119) dispatches to type-specific loan functions:

```c
// zenoh_macros.h:65-119
#define z_loan(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_loan, \
        z_owned_config_t : z_config_loan, \
        z_owned_session_t : z_session_loan, \
        z_owned_publisher_t : z_publisher_loan, \
        z_owned_subscriber_t : z_subscriber_loan, \
        /* ... 25+ more type cases ... */ \
    )(&this_)
```

The `z_loan_mut()` macro (lines 121-148) dispatches to mutable loan functions:

```c
// zenoh_macros.h:121-148
#define z_loan_mut(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_loan_mut, \
        z_owned_config_t : z_config_loan_mut, \
        z_owned_session_t : z_session_loan_mut, \
        /* ... 15+ more type cases ... */ \
    )(&this_)
```

The `z_move()` macro (lines 210-268) dispatches to type-specific move functions:

```c
// zenoh_macros.h:210-268
#define z_move(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_move, \
        z_owned_config_t : z_config_move, \
        z_owned_session_t : z_session_move, \
        z_owned_publisher_t : z_publisher_move, \
        z_owned_subscriber_t : z_subscriber_move, \
        /* ... 35+ more type cases ... */ \
    )(&this_)
```

The `z_closure()` macro (lines 537-547) dispatches to type-specific closure constructors:

```c
// zenoh_macros.h:537-547
#define z_closure(this_, call, drop, context) \
    _Generic((this_), \
        z_owned_closure_hello_t* : z_closure_hello, \
        z_owned_closure_matching_status_t* : z_closure_matching_status, \
        z_owned_closure_sample_t* : z_closure_sample, \
        z_owned_closure_zid_t* : z_closure_zid, \
        /* ... 4 more ... */ \
    )(this_, call, drop, context)
```

Additionally, all move functions are defined as `static inline` (lines 7-62):

```c
// zenoh_macros.h:7-62
static inline z_moved_bytes_t* z_bytes_move(z_owned_bytes_t* x) {
    return (z_moved_bytes_t*)(x);
}
static inline z_moved_config_t* z_config_move(z_owned_config_t* x) {
    return (z_moved_config_t*)(x);
}
static inline z_moved_session_t* z_session_move(z_owned_session_t* x) {
    return (z_moved_session_t*)(x);
}
static inline z_moved_publisher_t* z_publisher_move(z_owned_publisher_t* x) {
    return (z_moved_publisher_t*)(x);
}
static inline z_moved_subscriber_t* z_subscriber_move(z_owned_subscriber_t* x) {
    return (z_moved_subscriber_t*)(x);
}
static inline z_moved_shm_mut_t* z_shm_mut_move(z_owned_shm_mut_t* x) {
    return (z_moved_shm_mut_t*)(x);
}
// ... 56 total static inline move functions
```

#### 1.2 Why Dart FFI Cannot Call These

**Dart FFI resolves symbols from compiled shared libraries at link time.** C preprocessor macros and `static inline` functions do not produce exported symbols in the compiled `libzenohc.so`.

**Official Dart documentation references:**

- **Dart C interop guide** (https://dart.dev/interop/c-interop): The FFI mechanism uses `DynamicLibrary.open()` to load shared libraries and `lookup<NativeFunction<...>>()` to resolve function symbols by name. Only symbols present in the shared library's export table are callable.

- **ffigen documentation** (https://pub.dev/packages/ffigen): ffigen uses libclang to parse C headers and generates Dart bindings only for functions that produce linker symbols. The `include` filter in `ffigen.yaml` matches against function declarations, but `_Generic` macros and `static inline` functions are not function declarations -- they are preprocessor constructs that expand before the compiler sees them.

- **ffigen GitHub issue #146** (https://github.com/dart-archive/ffigen/issues/146): Confirms that `static inline` functions generate Dart bindings that fail at runtime with "symbol unavailable" because the compiled library does not export them. The recommended workaround is to wrap them in a C shim.

**Concrete proof:** Running `nm -D libzenohc.so | grep z_bytes_move` produces no output. The `static inline z_moved_bytes_t* z_bytes_move(...)` function is compiled into calling code by the C compiler and never appears as an exported symbol.

Similarly, `_Generic` macros like `z_drop()`, `z_loan()`, `z_move()`, `z_closure()` produce zero symbols in the binary. They are preprocessor text substitutions that the C preprocessor resolves before compilation begins.

#### 1.3 How the C Shim Resolves This

The shim wraps every needed `static inline` or macro invocation in a real, exported C function with the `zd_` prefix. Each shim function calls the macro/inline internally, and the C compiler resolves the macro/inline at compile time within `zenoh_dart.c`. The result is a real symbol in `libzenoh_dart.so`.

**Example -- Drop pattern:**

zenoh-c requires calling `z_config_drop(z_config_move(config))`, where `z_config_move` is `static inline` and `z_config_drop` is a `ZENOHC_API` function that accepts `z_moved_config_t*`:

```c
// src/zenoh_dart.c:42-44
FFI_PLUGIN_EXPORT void zd_config_drop(z_owned_config_t* config) {
  z_config_drop(z_config_move(config));
}
```

Dart calls `zd_config_drop` (a real exported symbol), which internally calls the `static inline` `z_config_move` and the API function `z_config_drop`. The same pattern is applied consistently:

| Shim function | Wraps | Inline/macro involved |
|---------------|-------|-----------------------|
| `zd_config_drop` | `z_config_drop(z_config_move(...))` | `z_config_move` is `static inline` |
| `zd_bytes_drop` | `z_bytes_drop(z_bytes_move(...))` | `z_bytes_move` is `static inline` |
| `zd_subscriber_drop` | `z_subscriber_drop(z_subscriber_move(...))` | `z_subscriber_move` is `static inline` |
| `zd_publisher_drop` | `z_publisher_drop(z_publisher_move(...))` | `z_publisher_move` is `static inline` |
| `zd_session_drop` | `z_session_drop(z_session_move(...))` | `z_session_move` is `static inline` |
| `zd_string_drop` | `z_string_drop(z_string_move(...))` | `z_string_move` is `static inline` |
| `zd_shm_mut_drop` | `z_shm_mut_drop(z_shm_mut_move(...))` | `z_shm_mut_move` is `static inline` |
| `zd_shm_provider_drop` | `z_shm_provider_drop(z_shm_provider_move(...))` | `z_shm_provider_move` is `static inline` |

**Example -- Session open:**

`z_open` is a `ZENOHC_API` function, but it requires `z_moved_config_t*` as its second parameter, which can only be obtained from `z_config_move()` (a `static inline`):

```c
// zenoh_commons.h:3796-3799
ZENOHC_API
z_result_t z_open(struct z_owned_session_t *this_,
                  struct z_moved_config_t *config,
                  const struct z_open_options_t *_options);
```

The shim wraps it:

```c
// src/zenoh_dart.c:54-57
FFI_PLUGIN_EXPORT int zd_open_session(z_owned_session_t* session,
                                      z_owned_config_t* config) {
  return z_open(session, z_config_move(config), NULL);
}
```

**Example -- Publisher put:**

`z_publisher_put` requires `z_moved_bytes_t*` from `z_bytes_move()` (static inline), plus `z_moved_encoding_t*` from `z_encoding_move()` (static inline):

```c
// src/zenoh_dart.c:368-386
FFI_PLUGIN_EXPORT int zd_publisher_put(
    const z_loaned_publisher_t* publisher,
    z_owned_bytes_t* payload,
    const char* encoding,
    z_owned_bytes_t* attachment) {
  z_publisher_put_options_t opts;
  z_publisher_put_options_default(&opts);
  if (encoding != NULL) {
    z_owned_encoding_t owned_encoding;
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);  // static inline
  }
  if (attachment != NULL) {
    opts.attachment = z_bytes_move(attachment);          // static inline
  }
  return z_publisher_put(publisher, z_bytes_move(payload), &opts);  // static inline
}
```

---

### Pattern 2: Opaque Struct Sizes Unknown to Dart

#### 2.1 The Problem in zenoh-c

All zenoh-c owned types are defined as opaque byte arrays whose sizes are determined at zenoh-c compile time. The internal layout is hidden behind `uint8_t _0[N]` padding.

**Evidence** (`extern/zenoh-c/include/zenoh_opaque.h`):

```c
// zenoh_opaque.h:443-445
typedef struct ALIGN(8) z_owned_config_t {
  uint8_t _0[2008];
} z_owned_config_t;

// zenoh_opaque.h:683-685
typedef struct ALIGN(8) z_owned_session_t {
  uint8_t _0[8];
} z_owned_session_t;

// zenoh_opaque.h:209-211
typedef struct ALIGN(8) z_owned_bytes_t {
  uint8_t _0[40];
} z_owned_bytes_t;
```

These sizes (2008, 8, 40 bytes) are compile-time constants in the zenoh-c Rust build, injected via cbindgen. They can change between zenoh-c versions without notice.

#### 2.2 Why Dart FFI Cannot Determine These Sizes

**Dart's `sizeOf<T>()` only works for types whose layout is known to Dart at compile time.**

**Official Dart documentation references:**

- **`sizeOf` function** (https://api.dart.dev/stable/dart-ffi/sizeOf.html): "Number of bytes used by native type T." The type `T` must be a concrete `dart:ffi` struct type with known field layout. For `Opaque` types, `sizeOf` is not defined.

- **`Opaque` class** (https://api.dart.dev/stable/dart-ffi/Opaque-class.html): "Opaque's subtypes represent opaque types in C. Opaque's subtypes are not constructible in the Dart code and serve purely as markers in type signatures." You cannot call `sizeOf<Opaque>()` or allocate an `Opaque` struct from Dart.

In the `ffigen.yaml`, all zenoh-c types are mapped to `Opaque`:

```yaml
# packages/zenoh/ffigen.yaml
type-map:
  typedefs:
    z_owned_config_t:
      lib: ffi
      c-type: Opaque
      dart-type: Opaque
    z_owned_session_t:
      lib: ffi
      c-type: Opaque
      dart-type: Opaque
    z_owned_bytes_t:
      lib: ffi
      c-type: Opaque
      dart-type: Opaque
    # ... 26 more opaque type mappings
```

This means Dart has no way to know that `z_owned_config_t` is 2008 bytes or that `z_owned_session_t` is 8 bytes. Dart cannot call `sizeOf<z_owned_config_t>()` because `z_owned_config_t` is mapped to `Opaque`, which has no size.

#### 2.3 How the C Shim Resolves This

The shim provides `sizeof` functions that return the runtime size of each opaque type:

```c
// src/zenoh_dart.c:23-25
FFI_PLUGIN_EXPORT size_t zd_config_sizeof(void) {
  return sizeof(z_owned_config_t);   // resolves to 2008 at compile time
}

// src/zenoh_dart.c:50-52
FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void) {
  return sizeof(z_owned_session_t);  // resolves to 8 at compile time
}

// src/zenoh_dart.c:73-75
FFI_PLUGIN_EXPORT size_t zd_bytes_sizeof(void) {
  return sizeof(z_owned_bytes_t);    // resolves to 40 at compile time
}
```

There are 9 `sizeof` functions total: `zd_config_sizeof`, `zd_session_sizeof`, `zd_view_keyexpr_sizeof`, `zd_bytes_sizeof`, `zd_string_sizeof`, `zd_view_string_sizeof`, `zd_subscriber_sizeof`, `zd_publisher_sizeof`, `zd_shm_provider_sizeof`, `zd_shm_mut_sizeof`.

Dart uses these at runtime to allocate correctly-sized memory:

```dart
// packages/zenoh/lib/src/config.dart:26
Config() : _ptr = calloc.allocate(bindings.zd_config_sizeof()) {

// packages/zenoh/lib/src/session.dart:37-38
static Session open({Config? config}) {
  final size = bindings.zd_session_sizeof();
  final Pointer<Void> ptr = calloc.allocate(size);

// packages/zenoh/lib/src/bytes.dart:31
factory ZBytes.fromString(String value) {
  final Pointer<Void> ptr = calloc.allocate(bindings.zd_bytes_sizeof());
```

This pattern ensures Dart allocates exactly the right number of bytes, even if the sizes change in a future zenoh-c version. The Dart code never hardcodes any struct size.

---

### Pattern 3: Options Structs with Non-Trivial Initialization

#### 3.1 The Problem in zenoh-c

zenoh-c API functions accept options structs that must be initialized with `_default()` functions before use. The options structs contain `z_moved_*_t*` pointer fields that encode ownership transfer.

**Evidence** (`extern/zenoh-c/include/zenoh_commons.h`):

The `z_put_options_t` struct (lines 808-828):

```c
// zenoh_commons.h:808-828
typedef struct z_put_options_t {
  struct z_moved_encoding_t *encoding;
  enum z_congestion_control_t congestion_control;
  enum z_priority_t priority;
  bool is_express;
  struct z_moved_bytes_t *attachment;
  z_timestamp_t *timestamp;
  struct z_moved_source_info_t *source_info;
} z_put_options_t;
```

This struct contains `z_moved_encoding_t*` and `z_moved_bytes_t*` -- these are *moved* pointer types that require `z_encoding_move()` and `z_bytes_move()` (both `static inline`) to produce.

The `z_put` function signature (lines 4061-4065):

```c
// zenoh_commons.h:4061-4065
ZENOHC_API
z_result_t z_put(const struct z_loaned_session_t *session,
                 const struct z_loaned_keyexpr_t *key_expr,
                 struct z_moved_bytes_t *payload,
                 struct z_put_options_t *options);
```

The payload parameter is `z_moved_bytes_t*`, which requires `z_bytes_move()` (`static inline`).

#### 3.2 Why Dart FFI Cannot Manage This

There are two compounding problems:

1. **The options struct fields include moved pointer types.** To set `opts.encoding = z_encoding_move(&owned)`, Dart would need to (a) call `z_encoding_move` (a `static inline` -- no symbol) and (b) write the resulting pointer into a specific struct field offset. But the struct is `Opaque`, so Dart cannot determine field offsets.

2. **The `_default()` initializer writes to struct internals.** `z_put_options_default(&opts)` must be called to set safe defaults before selectively overriding fields. While `z_put_options_default` is a real `ZENOHC_API` function (line 4069), Dart cannot modify the struct fields afterwards because the struct is opaque.

**Official Dart documentation references:**

- **`Opaque` class** (https://api.dart.dev/stable/dart-ffi/Opaque-class.html): Opaque types cannot have their fields read or written from Dart. They are pass-through markers for pointer types only.

- **`Struct` class** (https://api.dart.dev/stable/dart-ffi/Struct-class.html): To access struct fields from Dart, the struct must extend `Struct` with explicit `@Int32()`, `@Pointer()` etc. field annotations. The `ffigen.yaml` explicitly maps all zenoh-c types to `Opaque`, not `Struct`, because the internal layout is an implementation detail that changes between versions.

#### 3.3 How the C Shim Resolves This

The shim absorbs the entire options-struct lifecycle: stack-allocate, default-initialize, selectively override, and pass to the zenoh-c function -- all in C.

**Example -- `zd_put`:**

```c
// src/zenoh_dart.c:171-178
FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload) {
  z_put_options_t opts;
  z_put_options_default(&opts);     // initialize with safe defaults
  return z_put(session, keyexpr,
               z_bytes_move(payload),  // static inline
               &opts);
}
```

**Example -- `zd_declare_publisher` with selective field override:**

The publisher options struct has fields for encoding, congestion control, and priority. The shim uses sentinel values (`NULL`, `-1`) to distinguish "use default" from "override":

```c
// src/zenoh_dart.c:334-357
FFI_PLUGIN_EXPORT int zd_declare_publisher(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    const char* encoding,          // NULL = use default
    int congestion_control,        // -1 = use default
    int priority) {                // -1 = use default
  z_publisher_options_t opts;
  z_publisher_options_default(&opts);

  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);  // static inline
  }
  if (congestion_control >= 0) {
    opts.congestion_control = (z_congestion_control_t)congestion_control;
  }
  if (priority >= 0) {
    opts.priority = (z_priority_t)priority;
  }

  return z_declare_publisher(session, publisher, keyexpr, &opts);
}
```

Dart passes flat scalar parameters. The shim maps them into the options struct:

```dart
// packages/zenoh/lib/src/publisher.dart:46-53
final rc = bindings.zd_declare_publisher(
  loanedSession.cast(),
  ptr.cast(),
  loanedKe.cast(),
  encodingStr.cast(),               // NULL or string pointer
  congestionControl.index,          // 0 or 1
  priority.index + 1,               // 1-7 (zenoh-c is 1-indexed)
);
```

---

### Pattern 4: Closure Callbacks Across Thread Boundaries

#### 4.1 The Problem in zenoh-c

zenoh-c delivers asynchronous events (subscriber samples, matching status changes, scout results) via closure structs. These are C structs containing function pointers and a void* context.

**Evidence** (`extern/zenoh-c/include/zenoh_commons.h`):

The `z_owned_closure_sample_t` struct (lines 460-464):

```c
// zenoh_commons.h:460-464
typedef struct z_owned_closure_sample_t {
  void *_context;
  void (*_call)(struct z_loaned_sample_t *sample, void *context);
  void (*_drop)(void *context);
} z_owned_closure_sample_t;
```

The `z_closure_sample()` constructor function (lines 2106-2110):

```c
// zenoh_commons.h:2106-2110
ZENOHC_API
void z_closure_sample(struct z_owned_closure_sample_t *this_,
                      void (*call)(struct z_loaned_sample_t *sample, void *context),
                      void (*drop)(void *context),
                      void *context);
```

The `z_declare_subscriber()` function requires a moved closure (lines 2331-2336):

```c
// zenoh_commons.h:2331-2336
ZENOHC_API
z_result_t z_declare_subscriber(const struct z_loaned_session_t *session,
                                struct z_owned_subscriber_t *subscriber,
                                const struct z_loaned_keyexpr_t *key_expr,
                                struct z_moved_closure_sample_t *callback,
                                struct z_subscriber_options_t *options);
```

**Key constraints:**
- The `_call` function pointer is invoked by zenoh-c's internal Tokio runtime threads, not by the Dart isolate's thread.
- The `_call` function receives a `z_loaned_sample_t*` whose lifetime is limited to the callback invocation.
- The `_drop` function is called when the subscriber is undeclared, to free the context.

#### 4.2 Why Dart FFI Cannot Construct These Closures

There are three independent blocking constraints:

**Constraint A: `Pointer.fromFunction` requires static/top-level functions.**

Dart's `Pointer.fromFunction<NativeFunction>()` can only create native function pointers from static or top-level Dart functions. It cannot capture closures, instance methods, or lambdas.

**Official reference** -- `Pointer.fromFunction` API docs (https://api.dart.dev/stable/dart-ffi/Pointer/fromFunction.html):

> "Creates a Dart function pointer from a top-level or static Dart function. [...] The function must not be a closure (i.e. it must not capture any local variables)."

This means Dart cannot create a C function pointer that carries state (like which Dart `StreamController` to forward samples to). The callback would have no way to know its context.

**Constraint B: Callbacks are invoked on non-Dart threads.**

zenoh-c's subscriber callback runs on a Tokio runtime thread. Dart FFI callbacks created via `Pointer.fromFunction` are restricted to being called from the same thread that created them (the Dart isolate's mutator thread).

**Official reference** -- `Pointer.fromFunction` API docs (https://api.dart.dev/stable/dart-ffi/Pointer/fromFunction.html):

> "The pointer returned will remain alive for the duration of the current isolate's lifetime. After the isolate it was created in is terminated, invoking it from native code will cause undefined behavior."

**GitHub issue #48865** (https://github.com/dart-lang/sdk/issues/48865) confirms the threading restriction: calling a `Pointer.fromFunction` callback from a non-Dart thread causes undefined behavior.

**Constraint C: `NativeCallable` has limited threading support.**

Dart 3.1+ added `NativeCallable.listener` which CAN be called from any thread, but:
- It still cannot capture closures (must be a static/top-level function)
- Context must be passed via integer baton, not void* pointer
- It is cumbersome for complex multi-field data (5-element sample arrays)

**GitHub issue #52689** (https://github.com/dart-lang/sdk/issues/52689) discusses the limitations and workarounds.

#### 4.3 How the C Shim Resolves This

The shim implements a **NativePort callback bridge** pattern:

1. **C side:** A C callback function (static, with full access to zenoh-c types) extracts fields from the zenoh-c sample, constructs a `Dart_CObject` array, and posts it to a Dart `ReceivePort` via the thread-safe `Dart_PostCObject_DL`.

2. **Dart side:** A `ReceivePort` listener running on the Dart event loop receives the deserialized data and forwards it to a `StreamController<Sample>`.

**C side implementation** (`src/zenoh_dart.c:192-320`):

```c
// Context struct: heap-allocated, holds the Dart port number
typedef struct {
  Dart_Port_DL dart_port;
} zd_subscriber_context_t;

// Called by zenoh-c on its internal thread:
static void _zd_sample_callback(z_loaned_sample_t* sample, void* context) {
  zd_subscriber_context_t* ctx = (zd_subscriber_context_t*)context;

  // Extract fields using zenoh-c API (only C can call these on a non-Dart thread)
  z_view_string_t key_view;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_view);
  // ... extract payload, kind, attachment, encoding ...

  // Build a Dart_CObject array: [keyexpr, payload, kind, attachment, encoding]
  Dart_CObject* elements[5] = {&c_keyexpr, &c_payload, &c_kind,
                                &c_attachment, &c_encoding};
  Dart_CObject c_array;
  c_array.type = Dart_CObject_kArray;
  c_array.value.as_array.length = 5;
  c_array.value.as_array.values = elements;

  // Thread-safe post to Dart isolate
  Dart_PostCObject_DL(ctx->dart_port, &c_array);
}

// Called when subscriber is undeclared:
static void _zd_sample_drop(void* context) {
  free(context);  // free the heap-allocated context
}

FFI_PLUGIN_EXPORT int zd_declare_subscriber(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port) {           // <-- receives Dart port number, not a function pointer
  zd_subscriber_context_t* ctx = malloc(sizeof(zd_subscriber_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)dart_port;

  z_owned_closure_sample_t callback;
  z_closure_sample(&callback, _zd_sample_callback, _zd_sample_drop, ctx);

  return z_declare_subscriber(session, subscriber, keyexpr,
                              z_closure_sample_move(&callback), NULL);
}
```

**Dart side implementation** (`packages/zenoh/lib/src/subscriber.dart:29-76`):

```dart
static Subscriber declare(Pointer<Void> loanedSession, Pointer<Void> loanedKe) {
  final size = bindings.zd_subscriber_sizeof();
  final Pointer<Void> ptr = calloc.allocate(size);
  final receivePort = ReceivePort();
  final controller = StreamController<Sample>();

  // Runs on Dart event loop when C posts via Dart_PostCObject_DL
  receivePort.listen((dynamic message) {
    if (message is List) {
      final keyExpr = message[0] as String;
      final payloadBytes = message[1] as Uint8List;
      final kind = message[2] as int;
      final attachmentBytes = message[3] as Uint8List?;
      final encoding = message.length > 4 ? message[4] as String? : null;
      controller.add(Sample(
        keyExpr: keyExpr, payload: utf8.decode(payloadBytes),
        payloadBytes: payloadBytes,
        kind: kind == 0 ? SampleKind.put : SampleKind.delete,
        attachment: attachmentBytes != null ? utf8.decode(attachmentBytes) : null,
        encoding: encoding,
      ));
    }
  });

  // Pass the native port number (int64) to C -- not a function pointer
  final rc = bindings.zd_declare_subscriber(
    loanedSession.cast(), ptr.cast(), loanedKe.cast(),
    receivePort.sendPort.nativePort,
  );
  // ...
}
```

**Why `Dart_PostCObject_DL` is the correct bridge:**

- **Thread-safe:** Documented as safe to call from any thread (https://api.dart.dev/stable/dart-ffi/NativeApi/initializeApiDLData.html). This is the officially supported mechanism for native code running on non-Dart threads to deliver data to a Dart isolate.

- **Deep copy semantics:** `Dart_PostCObject_DL` copies the `Dart_CObject` data into the Dart heap before returning, so the C callback can safely free temporary buffers immediately after the call.

- **Requires initialization:** The Dart API DL must be initialized once via `Dart_InitializeApiDL(NativeApi.initializeApiDLData)`. This is why the shim has `zd_init_dart_api_dl()`, called during `_initBindings()`.

The same pattern is used for:

| Callback type | C shim function | Data posted | Dart receiver |
|---------------|----------------|-------------|---------------|
| Subscriber sample | `_zd_sample_callback` | 5-element array: [keyexpr, payload, kind, attachment, encoding] | `Subscriber.stream` |
| Matching status | `_zd_matching_status_callback` | Int64 (0 or 1) | `Publisher.matchingStatus` |
| Scout hello | `_zd_scout_hello_callback` | 3-element array: [zid_bytes, whatami, locators] + null sentinel | `Zenoh.scout()` future |

---

## Part B: Function-by-Function Analysis

### B.1 Initialization (2 functions)

#### `zd_init_dart_api_dl`

```c
FFI_PLUGIN_EXPORT intptr_t zd_init_dart_api_dl(void* data) {
  return Dart_InitializeApiDL(data);
}
```

**Problem solved:** `Dart_InitializeApiDL` must be called before any `Dart_PostCObject_DL` usage. Wrapping it as an exported symbol allows `ffigen` to generate a callable binding.

**Assessment:** Correct. The return value is propagated to Dart, which checks for non-zero failure. Called once during `_initBindings()`.

#### `zd_init_log`

```c
FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter) {
  zc_init_log_from_env_or(fallback_filter);
}
```

**Problem solved:** `zc_init_log_from_env_or` may be a macro or may not be directly bindable due to header complexity. The shim provides a stable symbol.

**Assessment:** Correct. Dart passes a `toNativeUtf8()` string and frees it after the call.

### B.2 Config (5 functions)

| Function | Wraps | Pattern Resolved |
|----------|-------|------------------|
| `zd_config_sizeof` | `sizeof(z_owned_config_t)` | Pattern 2: opaque size |
| `zd_config_default` | `z_config_default()` | Pattern 3: default init |
| `zd_config_insert_json5` | `z_config_loan_mut()` + `zc_config_insert_json5()` | Pattern 1: `z_config_loan_mut` is in `_Generic` loan_mut macro |
| `zd_config_loan` | `z_config_loan()` | Pattern 1: `z_config_loan` is in `_Generic` loan macro |
| `zd_config_drop` | `z_config_move()` + `z_config_drop()` | Pattern 1: `z_config_move` is `static inline` |

**Finding [C-1]: Drop pattern is correct and consistent.**

`z_config_move()` returns a `z_moved_config_t*` pointing into the same memory (reinterpret cast). `z_config_drop()` accepts the moved pointer and resets the original to gravestone state. This pattern is applied uniformly across all types.

### B.3 Session (4 functions)

#### `zd_open_session`

**Patterns resolved:** Pattern 1 (`z_config_move` is `static inline`), Pattern 3 (NULL options = defaults).

**Finding [C-2]: `z_close` return value is not checked in `zd_close_session`.**

```c
FFI_PLUGIN_EXPORT void zd_close_session(z_owned_session_t* session) {
  z_close(z_session_loan_mut(session), NULL);   // return value discarded
  z_session_drop(z_session_move(session));
}
```

**Severity:** Low. zenoh-cpp similarly ignores the return. Close-time errors are non-actionable.

### B.4 KeyExpr (4 functions)

All four functions resolve Pattern 1 (loan macro) and Pattern 2 (sizeof).

**Critical invariant:** `z_view_keyexpr_t` borrows the `expr` string. Dart's `KeyExpr` class holds `_nativeStr` and frees it only in `dispose()`.

### B.5 Bytes (6 functions)

Straightforward Pattern 1 + Pattern 2 wrappers.

**Finding [C-4]: `ZBytes.fromUint8List` copies data element-by-element.** Could use `nativeBuf.asTypedList(data.length).setAll(0, data)` for bulk copy.
**Severity:** Low (performance only).

### B.6 String / View String (8 functions)

Pure Pattern 1 wrappers. `zd_view_string_data` and `zd_view_string_len` save one FFI round-trip by combining loan + data/len.

### B.7 Put / Delete (2 functions)

Resolves all four patterns: `z_bytes_move` (Pattern 1), opaque sizes (Pattern 2), options struct (Pattern 3). No callbacks involved.

### B.8 Subscriber (3 functions)

Resolves all four patterns. The subscriber callback is the primary motivation for Pattern 4.

**Finding [C-5]: Payload passes through `z_bytes_to_string` in the callback.** Non-UTF-8 binary payloads may be corrupted.
**Severity:** Medium.

**Finding [C-7]: Error-path closure drop is defensively correct.** `z_closure_sample_move` in the error path produces a no-op on already-gravestone closures. Matches zenoh-c's idempotent drop guarantee.

### B.9 Publisher (7 functions)

Resolves all four patterns. Matching listener uses Pattern 4 (NativePort bridge).

**Finding [C-8]: Encoding ownership in options is correct.** `z_declare_publisher` is responsible for cleaning up moved values on failure per zenoh-c contract.

### B.10 Info (4 functions)

Resolves Pattern 1 (loan macros), Pattern 4 (ZID collection closure), and additionally handles **struct-by-value return** from `z_info_zid`.

`z_info_zid` returns `z_id_t` by value (a 16-byte struct). The shim copies it to a caller-provided buffer to avoid Dart FFI struct-by-value complications.

### B.11 Scout (3 functions)

Resolves all four patterns. Uses Pattern 4 with stack-allocated context (safe because `z_scout` blocks for `timeout_ms`).

**Finding [C-16]: Dart ignores `zd_scout` return value.** Scout failures are indistinguishable from "no entities found."
**Severity:** Medium.

### B.12 SHM (13 functions)

All guarded by `#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)`.

Resolves Pattern 1 (move/drop inlines), Pattern 2 (sizeof), and additionally flattens compound return types (`z_buf_layout_alloc_result_t` with status enum + buffer).

---

## Part C: Cross-Cutting Findings

### C.1 Memory Ownership Protocol

The Dart side implements a three-state model mirroring zenoh-c's gravestone semantics:

| State | Flags | Operations allowed |
|-------|-------|--------------------|
| **Live** | `_disposed=false, _consumed=false` | All operations |
| **Consumed** | `_consumed=true` | None (StateError) |
| **Disposed** | `_disposed=true` | `dispose()` (no-op) |

Enforced consistently across `Config`, `ZBytes`, `ShmMutBuffer`, `KeyExpr`.

**Finding [C-14]: `ZBytes.dispose()` leaks calloc wrapper when consumed.** The `ShmMutBuffer.dispose()` pattern is correct; `ZBytes` should match it.
**Severity:** Low.

### C.2 Allocator Consistency

**Finding [C-15]: `Zenoh.initLog` frees `malloc`'d string with `calloc.free`.**

```dart
final cStr = fallback.toNativeUtf8();  // uses malloc
// ...
calloc.free(cStr);  // should be malloc.free(cStr)
```

**Severity:** Low (works in practice because both resolve to libc `free()`).

### C.3 Thread Safety

All C callbacks use only stack-local variables + read-only context access + `Dart_PostCObject_DL` (thread-safe). No shared mutable state. Correct.

### C.4 Error Handling Completeness

All 19 error-returning shim functions are checked in Dart, except `zd_scout` (Finding C-16).

---

## Part D: Summary

### Pattern Resolution Matrix

| C shim function | Pattern 1 (macros/inlines) | Pattern 2 (sizeof) | Pattern 3 (options) | Pattern 4 (callbacks) |
|-----------------|:-:|:-:|:-:|:-:|
| `zd_init_dart_api_dl` | | | | X |
| `zd_config_sizeof` | | X | | |
| `zd_config_default` | | | X | |
| `zd_config_insert_json5` | X | | | |
| `zd_config_loan` | X | | | |
| `zd_config_drop` | X | | | |
| `zd_session_sizeof` | | X | | |
| `zd_open_session` | X | | X | |
| `zd_session_loan` | X | | | |
| `zd_close_session` | X | | | |
| `zd_view_keyexpr_sizeof` | | X | | |
| `zd_view_keyexpr_from_str` | X | | | |
| `zd_view_keyexpr_loan` | X | | | |
| `zd_keyexpr_as_view_string` | X | | | |
| `zd_bytes_sizeof` | | X | | |
| `zd_bytes_copy_from_str` | X | | | |
| `zd_bytes_copy_from_buf` | X | | | |
| `zd_bytes_to_string` | X | | | |
| `zd_bytes_loan` | X | | | |
| `zd_bytes_drop` | X | | | |
| `zd_string_sizeof` | | X | | |
| `zd_string_loan` | X | | | |
| `zd_string_data` | X | | | |
| `zd_string_len` | X | | | |
| `zd_string_drop` | X | | | |
| `zd_view_string_sizeof` | | X | | |
| `zd_view_string_data` | X | | | |
| `zd_view_string_len` | X | | | |
| `zd_put` | X | | X | |
| `zd_delete` | | | X | |
| `zd_subscriber_sizeof` | | X | | |
| `zd_declare_subscriber` | X | | | X |
| `zd_subscriber_drop` | X | | | |
| `zd_publisher_sizeof` | | X | | |
| `zd_declare_publisher` | X | | X | |
| `zd_publisher_loan` | X | | | |
| `zd_publisher_drop` | X | | | |
| `zd_publisher_put` | X | | X | |
| `zd_publisher_delete` | | | X | |
| `zd_publisher_keyexpr` | X | | | |
| `zd_publisher_declare_background_matching_listener` | X | | | X |
| `zd_publisher_get_matching_status` | | | | |
| `zd_info_zid` | X | | | |
| `zd_id_to_string` | | | | |
| `zd_info_routers_zid` | | | | X |
| `zd_info_peers_zid` | | | | X |
| `zd_scout` | X | | X | X |
| `zd_whatami_to_view_string` | | | | |
| `zd_shm_provider_sizeof` | | X | | |
| `zd_shm_provider_new` | X | | | |
| `zd_shm_provider_loan` | X | | | |
| `zd_shm_provider_drop` | X | | | |
| `zd_shm_provider_available` | | | | |
| `zd_shm_mut_sizeof` | | X | | |
| `zd_shm_provider_alloc` | X | | | |
| `zd_shm_provider_alloc_gc_defrag_blocking` | X | | | |
| `zd_shm_mut_loan_mut` | X | | | |
| `zd_shm_mut_data_mut` | | | | |
| `zd_shm_mut_len` | | | | |
| `zd_bytes_from_shm_mut` | X | | | |
| `zd_shm_mut_drop` | X | | | |

**Totals:** 40 functions resolve Pattern 1, 10 resolve Pattern 2, 8 resolve Pattern 3, 6 resolve Pattern 4.

### Findings Summary

| ID | Description | Severity |
|----|-------------|----------|
| C-1 | Drop pattern (`move` + `drop`) is correct and consistent | Positive |
| C-2 | `z_close` return value ignored in `zd_close_session` | Low |
| C-4 | `ZBytes.fromUint8List` element-by-element copy | Low |
| C-5 | Payload bytes pass through `z_bytes_to_string` in subscriber callback | Medium |
| C-7 | Subscriber closure error-path defensive drop is correct | Positive |
| C-8 | Encoding ownership in publisher options correct per zenoh-c contract | Positive |
| C-14 | `ZBytes.dispose()` leaks calloc wrapper when consumed | Low |
| C-15 | `Zenoh.initLog` frees `malloc`'d string with `calloc.free` | Low |
| C-16 | `Zenoh.scout` ignores `zd_scout` return value | Medium |

### References

| Document | URL |
|----------|-----|
| Dart C interop guide | https://dart.dev/interop/c-interop |
| `dart:ffi` API reference | https://api.dart.dev/stable/dart-ffi/dart-ffi-library.html |
| `Opaque` class docs | https://api.dart.dev/stable/dart-ffi/Opaque-class.html |
| `sizeOf` function docs | https://api.dart.dev/stable/dart-ffi/sizeOf.html |
| `Pointer.fromFunction` docs | https://api.dart.dev/stable/dart-ffi/Pointer/fromFunction.html |
| `Struct` class docs | https://api.dart.dev/stable/dart-ffi/Struct-class.html |
| `NativeApi.initializeApiDLData` | https://api.dart.dev/stable/dart-ffi/NativeApi/initializeApiDLData.html |
| ffigen package | https://pub.dev/packages/ffigen |
| ffigen inline issue #146 | https://github.com/dart-archive/ffigen/issues/146 |
| Dart SDK closure FFI #48865 | https://github.com/dart-lang/sdk/issues/48865 |
| Dart SDK closure FFI #52689 | https://github.com/dart-lang/sdk/issues/52689 |
| zenoh-c v1.7.2 headers | `extern/zenoh-c/include/zenoh_macros.h`, `zenoh_commons.h`, `zenoh_opaque.h` |
