# Proof: Why zenoh-c Requires a C Shim for Dart FFI

**Date:** 2026-03-09 (revised 2026-03-09)
**Companion to:** `CA-C_shim_audit.md`
**Purpose:** Demonstrate with concrete evidence that four patterns in zenoh-c's
public API are uncallable from Dart FFI, necessitating the C shim layer.
**Audience:** Expert C and Dart code reviewers verifying C shim necessity.
**Dart SDK:** 3.11.0 (via FVM). All documentation references verified against
Dart 3.11.1 API docs (latest stable at time of writing).
**ffigen version:** 20.1.1 (latest at time of writing).

---

## Table of Contents

1. [How Dart FFI Resolves Symbols](#1-how-dart-ffi-resolves-symbols)
2. [Pattern A: `static inline` Move Functions](#2-pattern-a-static-inline-move-functions)
3. [Pattern B: C11 `_Generic` Polymorphic Macros](#3-pattern-b-c11-_generic-polymorphic-macros)
4. [Pattern C: Options Struct Initialization](#4-pattern-c-options-struct-initialization)
5. [Pattern D: Opaque Type Sizes](#5-pattern-d-opaque-type-sizes)
6. [End-to-End Worked Example: `z_put`](#6-end-to-end-worked-example-z_put)
7. [References](#7-references)

---

## 1. How Dart FFI Resolves Symbols

### 1.1 Dart FFI Is C-Only

The `dart:ffi` library documentation (Dart 3.11.1) states:

> "Foreign Function Interface for interoperability with the C programming
> language."
> — [dart:ffi library overview](https://api.dart.dev/stable/latest/dart-ffi/dart-ffi-library.html) (Dart 3.11.1)

> "Dart mobile, command-line, and server apps running on the Dart Native
> platform can use the dart:ffi library to call native C APIs, and to read,
> write, allocate, and deallocate native memory."
> — [C interop guide](https://dart.dev/interop/c-interop) (reflects Dart 3.11.0)

The binding generator (`ffigen` v20.1.1) reinforces this constraint:

> "Note: FFIgen only supports parsing `C` headers, not `C++` headers."
> — [ffigen package](https://pub.dev/packages/ffigen)

**No Dart 3.x release has added support for calling C macros, `static inline`
functions, or C++ from `dart:ffi`.** The [Dart what's new](https://dart.dev/resources/whats-new)
page for releases 3.0 through 3.11 contains no FFI changes related to these
constructs. Dart "build hooks" (formerly "native assets") change how native
libraries are *built and bundled* but do not alter how `dart:ffi` resolves
symbols at runtime.

### 1.2 Symbol Resolution via `dlsym`

`DynamicLibrary.open` loads a shared library and provides access to its
symbols. The Dart 3.11.1 documentation states:

> "A dynamically loaded library is a mapping from symbols to memory addresses."
> — [DynamicLibrary class](https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary-class.html) (Dart 3.11.1)

`DynamicLibrary.lookup` resolves a symbol name to a memory address
— functionally equivalent to POSIX `dlsym(3)`:

> "Looks up a symbol in the DynamicLibrary and returns its address in memory."
> "Similar to the functionality of the dlsym(3) system call."
> "The symbol must be provided by the dynamic library."
> — [DynamicLibrary.lookup](https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary/lookup.html) (Dart 3.11.1)

**Consequence:** Only symbols present in the `.so`'s dynamic symbol table
(`nm -D`) are accessible. The following C constructs produce **no symbols**:

| Construct | Why No Symbol |
|-----------|---------------|
| `#define` macros | Text substitution by the preprocessor. No compiled code. |
| `static inline` functions | Internal linkage + inlined. Not exported. |
| `_Generic` macros | Compile-time type dispatch. Preprocessor construct. |
| C++ overloaded functions | Name-mangled. No stable C ABI symbol. |

### 1.2.1 Confirmed by ffigen Bug Tracker

The `ffigen` maintainers have explicitly addressed `static inline` functions
in two GitHub issues:

**Issue #146 ("Unavailable inline C function"):**
When `ffigen` previously generated bindings for inline functions like
`static inline uint16_t libusb_cpu_to_le16(...)`, the generated Dart code
referenced a dynamic library symbol that did not exist. The team's resolution
(merged in ffigen 2.0.1) was to **filter out inline functions** entirely:

> "We should skip them. (Generating an implementation for an arbitrary
> function would be very involved.)"
> — [dart-lang/ffigen#146](https://github.com/dart-lang/ffigen/issues/146), closed as COMPLETED

**Issue #459 ("Inline function available in compiled dylib, but no bindings generated"):**
Even when functions are marked `extern inline` (making them available in the
`.so`), `ffigen` initially refused to generate bindings. A partial fix (PR
#594) was merged to allow `extern inline` functions, but `static inline`
functions remain **permanently excluded** — they are not symbols, so there
is nothing to bind to.

> "Static inline functions don't appear in compiled dylibs and cannot be
> bound — this behavior is expected."
> — [dart-lang/native#459](https://github.com/dart-lang/native/issues/459)

**This confirms** that `static inline` is a known, permanent limitation of
Dart FFI, not an oversight that might be fixed in a future Dart release. The
ffigen team considers it expected behavior.

### 1.3 How the Shim Bridges This

The C shim (`src/zenoh_dart.c`) is compiled as a C translation unit that
`#include`s the zenoh-c headers. During compilation, the C compiler:

1. Expands all `#define` macros
2. Inlines all `static inline` functions
3. Resolves all `_Generic` dispatches

The shim's functions are marked `FFI_PLUGIN_EXPORT` (resolving to
`__attribute__((visibility("default")))`), which ensures they appear in
`libzenoh_dart.so`'s dynamic symbol table. Dart FFI can then call them
via `DynamicLibrary.lookup`.

---

## 2. Pattern A: `static inline` Move Functions

### 2.1 The Problem

zenoh-c uses an ownership model where consuming a resource requires
converting a `z_owned_*_t*` pointer to a `z_moved_*_t*` pointer. This
conversion is done via `static inline` functions defined in
`extern/zenoh-c/include/zenoh_macros.h`.

**There are 56 such functions.** Here are the ones used by the C shim:

```c
// zenoh_macros.h, lines 7-51 (C section)
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
static inline z_moved_shm_provider_t* z_shm_provider_move(z_owned_shm_provider_t* x) {
    return (z_moved_shm_provider_t*)(x);
}
static inline z_moved_string_t* z_string_move(z_owned_string_t* x) {
    return (z_moved_string_t*)(x);
}
static inline z_moved_encoding_t* z_encoding_move(z_owned_encoding_t* x) {
    return (z_moved_encoding_t*)(x);
}
// ... 47 more variants for other types
```

These are pointer casts at the C level — they reinterpret the same memory
address as a different pointer type. But they are `static inline`, meaning:

- `static` → internal linkage (not visible outside the translation unit)
- `inline` → the compiler may substitute the function body at the call site

**Neither property produces an exported symbol.**

### 2.2 Symbol Table Proof

Running `nm -D` on the compiled `libzenohc.so` confirms these symbols do
not exist:

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_bytes_move
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_config_move
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_session_move
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_string_move
(no output)
```

Zero results. These functions exist only in the header file. The linker
never sees them. Dart FFI's `DynamicLibrary.lookup('z_bytes_move')` would
throw an `ArgumentError`.

### 2.3 Why These Are Required

The move functions are not optional convenience wrappers. zenoh-c's core
API functions **require** `z_moved_*_t*` parameters. Without the move
functions, these core functions cannot be called:

```c
// zenoh_commons.h — actual exported function signatures

// z_open REQUIRES z_moved_config_t* (line 3796)
ZENOHC_API z_result_t z_open(
    struct z_owned_session_t *this_,
    struct z_moved_config_t *config,        // ← requires move
    const struct z_open_options_t *_options);

// z_put REQUIRES z_moved_bytes_t* (line 4062)
ZENOHC_API z_result_t z_put(
    const struct z_loaned_session_t *session,
    const struct z_loaned_keyexpr_t *key_expr,
    struct z_moved_bytes_t *payload,         // ← requires move
    struct z_put_options_t *options);

// z_config_drop REQUIRES z_moved_config_t* (line 2214)
ZENOHC_API void z_config_drop(struct z_moved_config_t *this_);  // ← requires move

// z_bytes_drop REQUIRES z_moved_bytes_t* (line 1564)
ZENOHC_API void z_bytes_drop(struct z_moved_bytes_t *this_);    // ← requires move

// z_session_drop REQUIRES z_moved_session_t* (line 4706)
ZENOHC_API void z_session_drop(struct z_moved_session_t *this_);  // ← requires move

// z_publisher_put REQUIRES z_moved_bytes_t* (line 4043)
ZENOHC_API z_result_t z_publisher_put(
    const struct z_loaned_publisher_t *this_,
    struct z_moved_bytes_t *payload,         // ← requires move
    struct z_publisher_put_options_t *options);

// z_declare_subscriber REQUIRES z_moved_closure_sample_t* (line 2331)
ZENOHC_API z_result_t z_declare_subscriber(
    const struct z_loaned_session_t *session,
    struct z_owned_subscriber_t *subscriber,
    const struct z_loaned_keyexpr_t *key_expr,
    struct z_moved_closure_sample_t *callback,  // ← requires move
    struct z_subscriber_options_t *options);
```

These functions **are** exported (confirmed via `nm -D`):

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_open$"
000000000039acb0 T z_open

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_put$"
000000000039e3f0 T z_put

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_config_drop$"
000000000038f790 T z_config_drop

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_bytes_drop$"
000000000038a320 T z_bytes_drop
```

**The functions exist. Their required parameter types can only be
constructed via functions that do not exist.** This is the fundamental
barrier.

### 2.4 What the Moved Types Actually Are

The `z_moved_*_t` types are wrapper structs defined in `zenoh_commons.h`:

```c
// zenoh_commons.h, lines 318-320
typedef struct z_moved_bytes_t {
    struct z_owned_bytes_t _this;
} z_moved_bytes_t;

// zenoh_commons.h, lines 490-492
typedef struct z_moved_config_t {
    struct z_owned_config_t _this;
} z_moved_config_t;

// zenoh_commons.h, lines 1009-1011
typedef struct z_moved_session_t {
    struct z_owned_session_t _this;
} z_moved_session_t;
```

At the machine level, `z_moved_bytes_t*` and `z_owned_bytes_t*` point to
the same memory — the wrapper struct has the same layout as its single
member. The `static inline` move function is an identity cast. A C compiler
resolves this at compile time with zero runtime cost.

**Could Dart perform this cast directly?** In theory, since it's an identity
cast (same pointer value, different type), Dart could pass a `Pointer<Void>`
and the C function would accept it. But:

1. Dart FFI has no mechanism to express the type distinction between
   `z_owned_bytes_t*` and `z_moved_bytes_t*` — both would be
   `Pointer<Void>`.
2. `ffigen` (v20.1.1) **permanently excludes** `static inline` functions
   from binding generation. The ffigen team confirmed this is expected
   behavior, not a bug (see [dart-lang/native#459](https://github.com/dart-lang/native/issues/459)
   and [dart-lang/ffigen#146](https://github.com/dart-lang/ffigen/issues/146)).
3. Even if Dart passed the raw pointer, the type safety that the move
   functions provide (preventing accidental reuse of consumed resources)
   would be lost entirely.

### 2.5 How the C Shim Solves This

The C shim calls the `static inline` move functions at compile time and
exports the result as real functions:

```c
// src/zenoh_dart.c — the shim resolves z_config_move at compile time

FFI_PLUGIN_EXPORT void zd_config_drop(z_owned_config_t* config) {
    z_config_drop(z_config_move(config));
    //            ^^^^^^^^^^^^^^^^^^^^^^
    //            static inline call resolved at compile time
    //            becomes a pointer cast in the compiled .so
}

FFI_PLUGIN_EXPORT int zd_open_session(z_owned_session_t* session,
                                      z_owned_config_t* config) {
    return z_open(session, z_config_move(config), NULL);
    //                     ^^^^^^^^^^^^^^^^^^^^^^
    //                     static inline, resolved at compile time
}

FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload) {
    z_put_options_t opts;
    z_put_options_default(&opts);
    return z_put(session, keyexpr, z_bytes_move(payload), &opts);
    //                             ^^^^^^^^^^^^^^^^^^^^^
    //                             static inline, resolved at compile time
}
```

Dart calls `zd_config_drop` (a real exported symbol). Inside that function,
`z_config_move` was expanded by the C compiler at compile time. The machine
code in `libzenoh_dart.so` simply passes the pointer to `z_config_drop` —
the move function has been compiled away into the shim.

---

## 3. Pattern B: C11 `_Generic` Polymorphic Macros

### 3.1 The Problem

zenoh-c provides convenience macros that dispatch to the correct
type-specific function based on the argument type. These use C11's
`_Generic` keyword, which is a compile-time type-selection mechanism.

From `extern/zenoh-c/include/zenoh_macros.h`:

**`z_loan` macro** (lines 65-119, **51 branches**):

```c
#define z_loan(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_loan, \
        z_owned_config_t : z_config_loan, \
        z_owned_encoding_t : z_encoding_loan, \
        z_owned_publisher_t : z_publisher_loan, \
        z_owned_session_t : z_session_loan, \
        z_owned_shm_mut_t : z_shm_mut_loan, \
        z_owned_shm_provider_t : z_shm_provider_loan, \
        z_owned_string_t : z_string_loan, \
        z_owned_subscriber_t : z_subscriber_loan, \
        z_view_keyexpr_t : z_view_keyexpr_loan, \
        z_view_string_t : z_view_string_loan, \
        /* ... 40 more branches ... */ \
    )(&this_)
```

**`z_drop` macro** (lines 150-208, **48 branches**):

```c
#define z_drop(this_) \
    _Generic((this_), \
        z_moved_bytes_t* : z_bytes_drop, \
        z_moved_config_t* : z_config_drop, \
        z_moved_publisher_t* : z_publisher_drop, \
        z_moved_session_t* : z_session_drop, \
        z_moved_shm_mut_t* : z_shm_mut_drop, \
        z_moved_shm_provider_t* : z_shm_provider_drop, \
        z_moved_string_t* : z_string_drop, \
        z_moved_subscriber_t* : z_subscriber_drop, \
        /* ... 40 more branches ... */ \
    )(this_)
```

**`z_move` macro** (lines 210-268, **56 branches**):

```c
#define z_move(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_move, \
        z_owned_config_t : z_config_move, \
        z_owned_publisher_t : z_publisher_move, \
        z_owned_session_t : z_session_move, \
        z_owned_shm_mut_t : z_shm_mut_move, \
        z_owned_shm_provider_t : z_shm_provider_move, \
        z_owned_string_t : z_string_move, \
        z_owned_subscriber_t : z_subscriber_move, \
        /* ... 48 more branches ... */ \
    )(&this_)
```

**`z_loan_mut` macro** (lines 121-148, **25 branches**):

```c
#define z_loan_mut(this_) \
    _Generic((this_), \
        z_owned_bytes_t : z_bytes_loan_mut, \
        z_owned_config_t : z_config_loan_mut, \
        z_owned_publisher_t : z_publisher_loan_mut, \
        z_owned_session_t : z_session_loan_mut, \
        z_owned_shm_mut_t : z_shm_mut_loan_mut, \
        /* ... 20 more branches ... */ \
    )(&this_)
```

### 3.2 Why `_Generic` Produces No Symbol

`_Generic` is defined in ISO C11 (§6.5.1.1). It is evaluated entirely at
compile time. The compiler:

1. Examines the type of the controlling expression
2. Selects the matching association
3. Emits a direct call to the selected function

No code is generated for the `_Generic` dispatch itself. The macro `z_loan`
does not appear as a symbol in `libzenohc.so` because it is a preprocessor
macro — it is expanded before compilation begins.

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_loan$"
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_drop$"
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_move$"
(no output)
```

### 3.3 Impact on the C Shim

The `_Generic` macros themselves are not used by the C shim. The shim calls
the **monomorphic** functions directly (e.g., `z_bytes_loan` instead of
`z_loan`). The monomorphic loan functions are exported:

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_bytes_loan$"
000000000038ad40 T z_bytes_loan

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_config_loan$"
(found)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep " T z_session_loan$"
(found)
```

**However,** the `z_move` macro dispatches to the `static inline` move
functions (Pattern A). So `z_move(myConfig)` expands to
`z_config_move(&myConfig)`, which is `static inline` and not exported.
The `_Generic` layer compounds the `static inline` problem — it's a macro
wrapping a non-exported function.

The C shim bypasses both layers by calling the monomorphic functions
directly and handling move semantics explicitly:

```c
// Instead of: z_drop(z_move(config))  — two macros, one non-exported function
// The shim does:
z_config_drop(z_config_move(config));
// z_config_drop → exported real function (found via nm -D)
// z_config_move → static inline, resolved at shim compile time
```

---

## 4. Pattern C: Options Struct Initialization

### 4.1 The Problem

zenoh-c functions take options structs that must be initialized before use.
The initialization functions are real exported functions:

```c
// zenoh_commons.h, line 4069
ZENOHC_API void z_put_options_default(struct z_put_options_t *this_);

// zenoh_commons.h, line 4030
ZENOHC_API void z_publisher_options_default(struct z_publisher_options_t *this_);
```

Confirmed exported:

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_put_options_default
000000000039f020 T z_put_options_default

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep z_publisher_options_default
000000000039da30 T z_publisher_options_default
```

**These functions are callable from Dart FFI.** The barrier is not the
initialization function itself, but the **combination** of:

1. Allocating the options struct with the correct size
2. Initializing it via the default function
3. Setting fields that require move semantics (`opts.encoding = z_encoding_move(...)`)
4. Passing it to the target function (`z_put(session, keyexpr, z_bytes_move(payload), &opts)`)

Step 3 requires `z_encoding_move` — a `static inline` function (Pattern A).
Step 4 requires `z_bytes_move` — also `static inline`.

### 4.2 The Struct Layout Problem

Even if Dart could call `z_put_options_default`, it would need to:

1. Know `sizeof(z_put_options_t)` to allocate native memory
2. Know the field offsets to set encoding, congestion control, etc.

The struct layout is defined in `zenoh_commons.h`:

```c
typedef struct z_put_options_t {
    struct z_moved_encoding_t *encoding;
    z_congestion_control_t congestion_control;
    z_priority_t priority;
    bool is_express;
    struct z_moved_bytes_t *attachment;
    z_reliability_t reliability;
    const struct z_loaned_timestamp_t *timestamp;
    struct z_moved_source_info_t *source_info;
} z_put_options_t;
```

This struct has **8 fields** with platform-dependent alignment. It contains
pointer types (`z_moved_encoding_t*`, `z_moved_bytes_t*`) that Dart FFI
can represent as `Pointer<Void>`, but:

- The layout changes between zenoh-c versions (no ABI stability guarantee)
- Setting the `encoding` field requires `z_encoding_move` (`static inline`)
- Setting the `attachment` field requires `z_bytes_move` (`static inline`)

### 4.3 How the C Shim Solves This

The shim internalizes the entire options workflow — allocation,
initialization, field setting, and the consuming function call:

```c
// src/zenoh_dart.c — zd_put internalizes the options struct

FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload) {
    z_put_options_t opts;             // stack-allocated, correct size
    z_put_options_default(&opts);     // initialized with defaults
    return z_put(session, keyexpr, z_bytes_move(payload), &opts);
    //                             ^^^^^^^^^^^^^^^^^^ static inline resolved
}
```

```c
// src/zenoh_dart.c — zd_declare_publisher uses sentinel params

FFI_PLUGIN_EXPORT int zd_declare_publisher(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    const char* encoding,         // NULL = default
    int congestion_control,       // -1 = default
    int priority) {               // -1 = default
    z_publisher_options_t opts;
    z_publisher_options_default(&opts);

    z_owned_encoding_t owned_encoding;
    if (encoding != NULL) {
        z_encoding_from_str(&owned_encoding, encoding);
        opts.encoding = z_encoding_move(&owned_encoding);
        //              ^^^^^^^^^^^^^^^ static inline, resolved at compile time
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

**Dart sees simple scalar parameters** (strings, ints with sentinel values).
The options struct, its layout, and the move semantics are all hidden inside
the compiled shim.

### 4.4 Dart-Side Invocation

The Dart code that calls `zd_declare_publisher` passes flat parameters:

```dart
// packages/zenoh/lib/src/publisher.dart, lines 46-53
final rc = bindings.zd_declare_publisher(
    loanedSession.cast(),
    ptr.cast(),
    loanedKe.cast(),
    encodingStr.cast(),           // Pointer<Utf8> or nullptr
    congestionControl.index,      // int (0 or 1)
    priority.index + 1,           // int (1-7)
);
```

No options struct. No move functions. No layout knowledge.

---

## 5. Pattern D: Opaque Type Sizes

### 5.1 The Problem

zenoh-c types (`z_owned_session_t`, `z_owned_config_t`, etc.) are opaque
structs. Their internal layout is an implementation detail that may change
between versions. Dart must allocate native memory for these types before
passing them to zenoh-c functions like `z_open`, but Dart FFI has no
`sizeof()` operator for foreign types.

The Dart FFI `Pointer` class documentation (Dart 3.11.1) states:

> "Represents a pointer into the native C memory. Cannot be extended."
> — [Pointer class](https://api.dart.dev/stable/latest/dart-ffi/Pointer-class.html) (Dart 3.11.1)

The class is `final` — "This class can neither be extended, implemented,
nor mixed in." Dart FFI's `sizeOf<T>()` only works for `NativeType`
subclasses known at compile time (e.g., `Int32`, `Uint8`). It cannot compute
the size of arbitrary zenoh-c structs whose definitions are not expressed as
Dart FFI struct bindings.

### 5.2 How the C Shim Solves This

The shim exports `sizeof` queries as real functions:

```c
// src/zenoh_dart.c
FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void) {
    return sizeof(z_owned_session_t);
}

FFI_PLUGIN_EXPORT size_t zd_config_sizeof(void) {
    return sizeof(z_owned_config_t);
}

FFI_PLUGIN_EXPORT size_t zd_bytes_sizeof(void) {
    return sizeof(z_owned_bytes_t);
}

FFI_PLUGIN_EXPORT size_t zd_publisher_sizeof(void) {
    return sizeof(z_owned_publisher_t);
}

FFI_PLUGIN_EXPORT size_t zd_subscriber_sizeof(void) {
    return sizeof(z_owned_subscriber_t);
}

FFI_PLUGIN_EXPORT size_t zd_shm_provider_sizeof(void) {
    return sizeof(z_owned_shm_provider_t);
}

FFI_PLUGIN_EXPORT size_t zd_shm_mut_sizeof(void) {
    return sizeof(z_owned_shm_mut_t);
}

FFI_PLUGIN_EXPORT size_t zd_string_sizeof(void) {
    return sizeof(z_owned_string_t);
}

FFI_PLUGIN_EXPORT size_t zd_view_keyexpr_sizeof(void) {
    return sizeof(z_view_keyexpr_t);
}

FFI_PLUGIN_EXPORT size_t zd_view_string_sizeof(void) {
    return sizeof(z_view_string_t);
}
```

### 5.3 Dart-Side Usage

Every Dart wrapper class queries the size at construction time:

```dart
// packages/zenoh/lib/src/session.dart, lines 37-38
static Session open({Config? config}) {
    final size = bindings.zd_session_sizeof();    // query at runtime
    final Pointer<Void> ptr = calloc.allocate(size);  // allocate exactly

// packages/zenoh/lib/src/config.dart, line 26
Config() : _ptr = calloc.allocate(bindings.zd_config_sizeof()) {

// packages/zenoh/lib/src/bytes.dart, line 31
final Pointer<Void> ptr = calloc.allocate(bindings.zd_bytes_sizeof());

// packages/zenoh/lib/src/subscriber.dart, lines 33-34
final size = bindings.zd_subscriber_sizeof();
final Pointer<Void> ptr = calloc.allocate(size);

// packages/zenoh/lib/src/publisher.dart, lines 38-39
final size = bindings.zd_publisher_sizeof();
final Pointer<Void> ptr = calloc.allocate(size);

// packages/zenoh/lib/src/shm_provider.dart, lines 22-23
final size = bindings.zd_shm_provider_sizeof();
final Pointer<Void> ptr = calloc.allocate(size);
```

The `Pointer<Void>` type is Dart FFI's representation of an opaque pointer:

> "Void is not constructible in the Dart code and serves purely as marker
> in type signatures."
> — [Void class](https://api.dart.dev/stable/latest/dart-ffi/Void-class.html) (Dart 3.11.1)

For named opaque types, Dart FFI provides the `Opaque` base class:

> "Opaque's subtypes represent opaque types in C."
> "Opaque's subtypes are not constructible in the Dart code and serve purely
> as markers in type signatures."
> — [Opaque class](https://api.dart.dev/stable/latest/dart-ffi/Opaque-class.html) (Dart 3.11.1)

This project uses `Pointer<Void>` rather than `Opaque` subclasses because
the zenoh-c types are not defined in Dart FFI struct bindings — they are
allocated as raw memory blocks via `calloc.allocate(size)` where `size` is
queried at runtime from the C shim.

This pattern is version-safe: if zenoh-c changes the size of
`z_owned_session_t` in a future release, the Dart code automatically
allocates the correct amount because it queries at runtime.

---

## 6. End-to-End Worked Example: `z_put`

This section traces a single operation — publishing data on a key expression
— through all four patterns to show how they compound.

### 6.1 What a C Consumer Does

A C program calling `z_put` must:

```c
// 1. Allocate and initialize options (Pattern C)
z_put_options_t opts;
z_put_options_default(&opts);

// 2. Create payload bytes
z_owned_bytes_t payload;
z_bytes_copy_from_str(&payload, "Hello");

// 3. Call z_put with moved payload (Pattern A)
z_put(z_session_loan(&session),        // loan = may be inline
      z_view_keyexpr_loan(&keyexpr),   // loan = may be inline
      z_bytes_move(&payload),          // static inline — NOT exported
      &opts);
```

### 6.2 What Dart FFI Cannot Do

Dart FFI **can** call:
- `z_bytes_copy_from_str` — exported (`nm -D` confirms)
- `z_put` — exported (`000000000039e3f0 T z_put`)
- `z_put_options_default` — exported (`000000000039f020 T z_put_options_default`)
- `z_bytes_loan` — exported (`000000000038ad40 T z_bytes_loan`)

Dart FFI **cannot** call:
- `z_bytes_move` — `static inline`, not in symbol table
- `z_session_loan` — exported, but `z_loan` (`_Generic`) is not
- `sizeof(z_put_options_t)` — Dart cannot compute this

**The call chain breaks at `z_bytes_move`.** Even though `z_put` is a real
symbol, Dart cannot construct its third argument (`z_moved_bytes_t*`).

### 6.3 What the C Shim Does

```c
// src/zenoh_dart.c — zd_put flattens the entire chain

FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,   // already loaned by Dart
    const z_loaned_keyexpr_t* keyexpr,   // already loaned by Dart
    z_owned_bytes_t* payload) {          // owned, will be moved
    z_put_options_t opts;                // Pattern C: stack-allocated
    z_put_options_default(&opts);        // Pattern C: initialized
    return z_put(session, keyexpr,
                 z_bytes_move(payload),  // Pattern A: static inline resolved
                 &opts);                 // Pattern C: passed through
}
```

### 6.4 What Dart Calls

```dart
// packages/zenoh/lib/src/session.dart, lines 157-168
void put(String keyExpr, String value) {
    _withKeyExpr(keyExpr, (loanedSession, loanedKe) {
        final payload = ZBytes.fromString(value);
        final rc = bindings.zd_put(
            loanedSession.cast(),    // already loaned via zd_session_loan
            loanedKe.cast(),         // already loaned via zd_view_keyexpr_loan
            payload.nativePtr.cast(),// owned bytes, shim will move
        );
        payload.markConsumed();      // ownership transferred to zenoh-c
        if (rc != 0) {
            throw ZenohException('Put failed', rc);
        }
    });
}
```

### 6.5 The Full Call Chain

```
Dart: session.put('demo/test', 'Hello')
  → ZBytes.fromString('Hello')
    → calloc.allocate(bindings.zd_bytes_sizeof())     [Pattern D: sizeof query]
    → bindings.zd_bytes_copy_from_str(ptr, nativeStr)  [exported symbol]
  → bindings.zd_put(loanedSession, loanedKe, payloadPtr)  [shim function]
    → C shim: z_put_options_default(&opts)              [Pattern C: options init]
    → C shim: z_put(session, keyexpr,
                     z_bytes_move(payload),              [Pattern A: static inline]
                     &opts)                              [Pattern C: options pass]
      → libzenohc.so: z_put()                           [exported symbol]
  → payload.markConsumed()                               [Dart ownership tracking]
```

Four patterns, one operation. The C shim collapses all four into a single
FFI-callable function.

---

## 7. References

### 7.1 Dart FFI Official Documentation (all verified against Dart 3.11.1)

All `api.dart.dev/stable/latest/` URLs resolve to the current stable SDK
(Dart 3.11.1 at time of writing). Using `/latest/` ensures links remain
valid as new Dart versions are released.

| Document | URL | Verified SDK |
|----------|-----|-------------|
| dart:ffi library overview | https://api.dart.dev/stable/latest/dart-ffi/dart-ffi-library.html | 3.11.1 |
| C interop guide | https://dart.dev/interop/c-interop | 3.11.0 |
| DynamicLibrary class | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary-class.html | 3.11.1 |
| DynamicLibrary.open | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary/DynamicLibrary.open.html | 3.11.1 |
| DynamicLibrary.lookup | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary/lookup.html | 3.11.1 |
| lookupFunction | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibraryExtension/lookupFunction.html | 3.11.1 |
| NativeApi class | https://api.dart.dev/stable/latest/dart-ffi/NativeApi-class.html | 3.11.1 |
| initializeApiDLData | https://api.dart.dev/stable/latest/dart-ffi/NativeApi/initializeApiDLData.html | 3.11.1 |
| postCObject | https://api.dart.dev/stable/latest/dart-ffi/NativeApi/postCObject.html | 3.11.1 |
| Pointer class | https://api.dart.dev/stable/latest/dart-ffi/Pointer-class.html | 3.11.1 |
| Void class | https://api.dart.dev/stable/latest/dart-ffi/Void-class.html | 3.11.1 |
| Opaque class | https://api.dart.dev/stable/latest/dart-ffi/Opaque-class.html | 3.11.1 |
| ffigen package | https://pub.dev/packages/ffigen | v20.1.1 |
| Dart what's new | https://dart.dev/resources/whats-new | 3.11 |

### 7.2 ffigen Bug Tracker (confirming `static inline` exclusion)

| Issue | Status | Key Finding |
|-------|--------|-------------|
| [dart-lang/ffigen#146](https://github.com/dart-lang/ffigen/issues/146) | Closed (COMPLETED) | ffigen now **skips** inline functions: "We should skip them." |
| [dart-lang/native#459](https://github.com/dart-lang/native/issues/459) | Partially resolved | `extern inline` supported (PR #594); `static inline` **permanently excluded**: "don't appear in compiled dylibs — this behavior is expected" |

### 7.3 zenoh-c Source Files

| File | Content | Line Count |
|------|---------|------------|
| `extern/zenoh-c/include/zenoh_macros.h` | `static inline` moves, `_Generic` macros, C++ overloads | 1467 |
| `extern/zenoh-c/include/zenoh_commons.h` | Exported function signatures, struct typedefs | ~5000 |
| `src/zenoh_dart.h` | C shim header — 62 exported functions | 543 |
| `src/zenoh_dart.c` | C shim implementation | ~700 |

### 7.4 ISO C Standards

| Standard | Section | Content |
|----------|---------|---------|
| ISO C11 | §6.5.1.1 | `_Generic` selection — compile-time type dispatch |
| ISO C11 | §6.7.4 | `inline` function specifiers — no guarantee of external linkage |
| ISO C11 | §6.2.2 | `static` linkage — internal to translation unit |

### 7.5 Symbol Table Verification Commands

All commands run against `extern/zenoh-c/target/release/libzenohc.so`
(zenoh-c v1.7.2, built with `RUSTUP_TOOLCHAIN=stable`):

```bash
# Verify static inline functions are NOT exported
nm -D libzenohc.so | grep z_bytes_move     # (no output)
nm -D libzenohc.so | grep z_config_move    # (no output)
nm -D libzenohc.so | grep z_session_move   # (no output)

# Verify _Generic macros are NOT exported
nm -D libzenohc.so | grep "z_loan$"        # (no output)
nm -D libzenohc.so | grep "z_drop$"        # (no output)
nm -D libzenohc.so | grep "z_move$"        # (no output)

# Verify real functions ARE exported
nm -D libzenohc.so | grep " T z_put$"             # 000000000039e3f0 T z_put
nm -D libzenohc.so | grep " T z_open$"            # 000000000039acb0 T z_open
nm -D libzenohc.so | grep " T z_config_drop$"     # 000000000038f790 T z_config_drop
nm -D libzenohc.so | grep " T z_bytes_loan$"      # 000000000038ad40 T z_bytes_loan
nm -D libzenohc.so | grep " T z_bytes_drop$"      # 000000000038a320 T z_bytes_drop
nm -D libzenohc.so | grep " T z_session_drop$"    # 00000000003a70f0 T z_session_drop
nm -D libzenohc.so | grep " T z_put_options_default$"  # 000000000039f020 T z_put_options_default
```

---

## Summary

| Pattern | What It Is | Why Dart FFI Cannot Call It | How the Shim Resolves It |
|---------|-----------|---------------------------|--------------------------|
| **A: `static inline` move** | 56 identity-cast functions in `zenoh_macros.h` | `static` = internal linkage, `inline` = no exported symbol. `nm -D` confirms absence. | Shim calls them at compile time. The C compiler inlines the cast into the shim's exported function. |
| **B: `_Generic` macros** | 4 polymorphic macros with 51-56 branches each | Preprocessor construct. No symbol. Dispatches to move functions (Pattern A). | Shim calls monomorphic functions directly (`z_bytes_loan` not `z_loan`). |
| **C: Options structs** | Stack-allocated structs with fields requiring Pattern A | `sizeof` unknown to Dart. Fields require `z_*_move` (Pattern A). Layout is version-specific. | Shim allocates, initializes, sets fields, and passes — all in one exported function. |
| **D: Opaque type sizes** | `z_owned_session_t` etc. — sizes unknown to Dart | Dart FFI has no `sizeof()` for foreign types. | Shim exports `zd_*_sizeof()` functions. Dart queries at runtime. |

The four patterns are not independent barriers — they **compound**. A single
`z_put` call requires Pattern D (to allocate the payload), Pattern A (to
move the payload), and Pattern C (to create and pass options). The C shim
collapses all of these into one FFI-callable function with simple scalar
parameters.
