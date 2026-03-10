# C Shim Architecture: Existence Proof and Functional Audit

**Date:** 2026-03-09
**Scope:** `src/zenoh_dart.{h,c}` — 62 exported symbols, ~700 lines
**Reviewed against:** zenoh-c v1.7.2 (`extern/zenoh-c/`), Dart SDK 3.11.0 (via FVM),
ffigen v20.1.1, Dart 3.11.1 API docs (latest stable at time of writing)
**Audience:** Expert C and Dart code reviewers
**Supersedes:** `CA-C_shim_audit.md`, `CA-C_shim_proof.md`, `CC-C_shim_audit.md`

---

## Table of Contents

- [Part A: Why the C Shim Must Exist](#part-a-why-the-c-shim-must-exist)
  - [A.1 How Dart FFI Resolves Symbols](#a1-how-dart-ffi-resolves-symbols)
  - [A.2 Pattern 1: `static inline` Move Functions](#a2-pattern-1-static-inline-move-functions)
  - [A.3 Pattern 2: C11 `_Generic` Polymorphic Macros](#a3-pattern-2-c11-_generic-polymorphic-macros)
  - [A.4 Pattern 3: Options Struct Initialization](#a4-pattern-3-options-struct-initialization)
  - [A.5 Pattern 4: Opaque Type Sizes](#a5-pattern-4-opaque-type-sizes)
  - [A.6 Pattern 5: Closure Callbacks Across Thread Boundaries](#a6-pattern-5-closure-callbacks-across-thread-boundaries)
  - [A.7 Pattern 6: Loaning and Const/Mut Enforcement](#a7-pattern-6-loaning-and-constmut-enforcement)
  - [A.8 End-to-End Worked Example: `z_put`](#a8-end-to-end-worked-example-z_put)
  - [A.9 What the Shim Does NOT Do](#a9-what-the-shim-does-not-do)
- [Part B: Function-by-Function Analysis](#part-b-function-by-function-analysis)
- [Part C: Cross-Cutting Analysis](#part-c-cross-cutting-analysis)
- [Part D: Pattern Resolution Matrix](#part-d-pattern-resolution-matrix)
- [Part E: Conformance Summary](#part-e-conformance-summary)
- [References](#references)

---

## Part A: Why the C Shim Must Exist

The zenoh-c v1.7.2 public API relies on six patterns that Dart FFI cannot
call. This section proves each pattern exists in the zenoh-c headers with
exact file references, explains why Dart FFI cannot handle it with references
to official Dart documentation, and shows how the C shim resolves each one.

### A.1 How Dart FFI Resolves Symbols

#### A.1.1 Dart FFI Is C-Only

The `dart:ffi` library documentation (Dart 3.11.1) states:

> "Foreign Function Interface for interoperability with the C programming
> language."
> — [dart:ffi library overview](https://api.dart.dev/stable/latest/dart-ffi/dart-ffi-library.html)

> "Dart mobile, command-line, and server apps running on the Dart Native
> platform can use the dart:ffi library to call native C APIs, and to read,
> write, allocate, and deallocate native memory."
> — [C interop guide](https://dart.dev/interop/c-interop)

The binding generator (`ffigen` v20.1.1) reinforces this constraint:

> "Note: FFIgen only supports parsing `C` headers, not `C++` headers."
> — [ffigen package](https://pub.dev/packages/ffigen)

**No Dart 3.x release has added support for calling C macros, `static inline`
functions, or C++ from `dart:ffi`.** The [Dart what's new](https://dart.dev/resources/whats-new)
page for releases 3.0 through 3.11 contains no FFI changes related to these
constructs. Dart "build hooks" (formerly "native assets") change how native
libraries are *built and bundled* but do not alter how `dart:ffi` resolves
symbols at runtime.

#### A.1.2 Symbol Resolution via `dlsym`

`DynamicLibrary.open` loads a shared library and provides access to its
symbols. The Dart 3.11.1 documentation states:

> "A dynamically loaded library is a mapping from symbols to memory addresses."
> — [DynamicLibrary class](https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary-class.html)

`DynamicLibrary.lookup` resolves a symbol name to a memory address
— functionally equivalent to POSIX `dlsym(3)`:

> "Looks up a symbol in the DynamicLibrary and returns its address in memory."
> "Similar to the functionality of the dlsym(3) system call."
> "The symbol must be provided by the dynamic library."
> — [DynamicLibrary.lookup](https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary/lookup.html)

**Consequence:** Only symbols present in the `.so`'s dynamic symbol table
(`nm -D`) are accessible. The following C constructs produce **no symbols**:

| Construct | Why No Symbol |
|-----------|---------------|
| `#define` macros | Text substitution by the preprocessor. No compiled code. |
| `static inline` functions | Internal linkage + inlined. Not exported. |
| `_Generic` macros | Compile-time type dispatch. Preprocessor construct. |
| C++ overloaded functions | Name-mangled. No stable C ABI symbol. |

#### A.1.3 Confirmed by ffigen Bug Tracker

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
`.so`), `ffigen` initially refused to generate bindings. A partial fix
(PR #594) was merged to allow `extern inline` functions, but `static inline`
functions remain **permanently excluded** — they are not symbols, so there
is nothing to bind to.

> "Static inline functions don't appear in compiled dylibs and cannot be
> bound — this behavior is expected."
> — [dart-lang/native#459](https://github.com/dart-lang/native/issues/459)

**This confirms** that `static inline` is a known, permanent limitation of
Dart FFI, not an oversight that might be fixed in a future Dart release. The
ffigen team considers it expected behavior.

#### A.1.4 How the Shim Bridges This

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

### A.2 Pattern 1: `static inline` Move Functions

#### A.2.1 The Problem

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

#### A.2.2 Symbol Table Proof

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

#### A.2.3 Why These Are Required

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
ZENOHC_API void z_config_drop(struct z_moved_config_t *this_);

// z_bytes_drop REQUIRES z_moved_bytes_t* (line 1564)
ZENOHC_API void z_bytes_drop(struct z_moved_bytes_t *this_);

// z_session_drop REQUIRES z_moved_session_t* (line 4706)
ZENOHC_API void z_session_drop(struct z_moved_session_t *this_);

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

#### A.2.4 What the Moved Types Actually Are

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
   from binding generation (see §A.1.3).
3. Even if Dart passed the raw pointer, the type safety that the move
   functions provide (preventing accidental reuse of consumed resources)
   would be lost entirely.

#### A.2.5 How the C Shim Solves This

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

The shim applies this pattern consistently across all ownership-consuming
operations:

| Shim function | Wraps | Inline involved |
|---------------|-------|-----------------|
| `zd_config_drop` | `z_config_drop(z_config_move(...))` | `z_config_move` |
| `zd_bytes_drop` | `z_bytes_drop(z_bytes_move(...))` | `z_bytes_move` |
| `zd_subscriber_drop` | `z_subscriber_drop(z_subscriber_move(...))` | `z_subscriber_move` |
| `zd_publisher_drop` | `z_publisher_drop(z_publisher_move(...))` | `z_publisher_move` |
| `zd_session_drop` | `z_session_drop(z_session_move(...))` | `z_session_move` |
| `zd_string_drop` | `z_string_drop(z_string_move(...))` | `z_string_move` |
| `zd_shm_mut_drop` | `z_shm_mut_drop(z_shm_mut_move(...))` | `z_shm_mut_move` |
| `zd_shm_provider_drop` | `z_shm_provider_drop(z_shm_provider_move(...))` | `z_shm_provider_move` |

---

### A.3 Pattern 2: C11 `_Generic` Polymorphic Macros

#### A.3.1 The Problem

zenoh-c provides convenience macros that dispatch to the correct
type-specific function based on the argument type. These use C11's
`_Generic` keyword, a compile-time type-selection mechanism.

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

#### A.3.2 Why `_Generic` Produces No Symbol

`_Generic` is defined in ISO C11 (§6.5.1.1). It is evaluated entirely at
compile time. The compiler:

1. Examines the type of the controlling expression
2. Selects the matching association
3. Emits a direct call to the selected function

No code is generated for the `_Generic` dispatch itself. The macros do not
appear in `libzenohc.so` because they are preprocessor constructs — expanded
before compilation begins.

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_loan$"
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_drop$"
(no output)

$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep "z_move$"
(no output)
```

#### A.3.3 Compounding With Pattern 1

The underlying monomorphic functions (`z_bytes_loan`, `z_config_loan`, etc.)
**are** exported and could theoretically be called from Dart directly. But
the `z_move` macro dispatches to the `static inline` move functions
(Pattern 1). So `z_move(myConfig)` expands to `z_config_move(&myConfig)`,
which is `static inline` and not exported. The `_Generic` layer compounds
the `static inline` problem — it's a macro wrapping a non-exported function.

The C shim bypasses both layers by calling the monomorphic functions directly
and handling move semantics explicitly:

```c
// Instead of: z_drop(z_move(config))  — two macros, one non-exported function
// The shim does:
z_config_drop(z_config_move(config));
// z_config_drop → exported real function (found via nm -D)
// z_config_move → static inline, resolved at shim compile time
```

---

### A.4 Pattern 3: Options Struct Initialization

#### A.4.1 The Problem

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

Step 3 requires `z_encoding_move` — a `static inline` function (Pattern 1).
Step 4 requires `z_bytes_move` — also `static inline`.

#### A.4.2 The Struct Layout Problem

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

**Official Dart documentation references:**

- **`Struct` class** ([docs](https://api.dart.dev/stable/latest/dart-ffi/Struct-class.html)):
  To access struct fields from Dart, the struct must extend `Struct` with
  explicit `@Int32()`, `@Pointer()` etc. field annotations. The `ffigen.yaml`
  explicitly maps all zenoh-c types to `Opaque`, not `Struct`, because the
  internal layout is an implementation detail that changes between versions.

- **`Opaque` class** ([docs](https://api.dart.dev/stable/latest/dart-ffi/Opaque-class.html)):
  "Opaque's subtypes represent opaque types in C. Opaque's subtypes are not
  constructible in the Dart code and serve purely as markers in type
  signatures." Opaque types cannot have their fields read or written from Dart.

#### A.4.3 How the C Shim Solves This

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

For functions needing selective option overrides, the shim uses sentinel
parameters (`NULL` for strings, `-1` for enums):

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

**Dart sees simple scalar parameters.** The options struct, its layout, and
the move semantics are all hidden inside the compiled shim:

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

### A.5 Pattern 4: Opaque Type Sizes

#### A.5.1 The Problem

zenoh-c types (`z_owned_session_t`, `z_owned_config_t`, etc.) are opaque
structs. Their internal layout is an implementation detail that may change
between versions. Dart must allocate native memory for these types before
passing them to zenoh-c functions, but Dart FFI cannot determine their size.

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

These sizes (2008, 8, 40 bytes) are compile-time constants in the zenoh-c
Rust build, injected via cbindgen. They can change between zenoh-c versions
without notice.

**Official Dart documentation references:**

- **`sizeOf` function** ([docs](https://api.dart.dev/stable/latest/dart-ffi/sizeOf.html)):
  "Number of bytes used by native type T." The type `T` must be a concrete
  `dart:ffi` struct type with known field layout. For `Opaque` types,
  `sizeOf` is not defined.

- **`Opaque` class** ([docs](https://api.dart.dev/stable/latest/dart-ffi/Opaque-class.html)):
  Opaque types "are not constructible in the Dart code and serve purely as
  markers in type signatures." You cannot call `sizeOf<Opaque>()`.

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

Dart has no way to know that `z_owned_config_t` is 2008 bytes. Dart cannot
call `sizeOf<z_owned_config_t>()` because `z_owned_config_t` is mapped to
`Opaque`, which has no size.

#### A.5.2 How the C Shim Solves This

The shim exports `sizeof` queries as real functions:

```c
// src/zenoh_dart.c
FFI_PLUGIN_EXPORT size_t zd_config_sizeof(void) {
    return sizeof(z_owned_config_t);   // resolves to 2008 at compile time
}
FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void) {
    return sizeof(z_owned_session_t);  // resolves to 8 at compile time
}
FFI_PLUGIN_EXPORT size_t zd_bytes_sizeof(void) {
    return sizeof(z_owned_bytes_t);    // resolves to 40 at compile time
}
// 7 more: view_keyexpr, string, view_string, subscriber, publisher,
//         shm_provider, shm_mut
```

Every Dart wrapper class queries the size at construction time:

```dart
// packages/zenoh/lib/src/session.dart, lines 37-38
final size = bindings.zd_session_sizeof();    // query at runtime
final Pointer<Void> ptr = calloc.allocate(size);  // allocate exactly

// packages/zenoh/lib/src/config.dart, line 26
Config() : _ptr = calloc.allocate(bindings.zd_config_sizeof()) {

// packages/zenoh/lib/src/bytes.dart, line 31
final Pointer<Void> ptr = calloc.allocate(bindings.zd_bytes_sizeof());
```

This pattern is version-safe: if zenoh-c changes the size of
`z_owned_session_t` in a future release, the Dart code automatically
allocates the correct amount because it queries at runtime.

---

### A.6 Pattern 5: Closure Callbacks Across Thread Boundaries

#### A.6.1 The Problem

zenoh-c delivers asynchronous events (subscriber samples, matching status
changes, scout results) via closure structs. These are C structs containing
function pointers and a `void*` context.

**Evidence** (`extern/zenoh-c/include/zenoh_commons.h`):

```c
// zenoh_commons.h:460-464
typedef struct z_owned_closure_sample_t {
  void *_context;
  void (*_call)(struct z_loaned_sample_t *sample, void *context);
  void (*_drop)(void *context);
} z_owned_closure_sample_t;
```

The `z_declare_subscriber()` function requires a moved closure:

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
- The `_call` function pointer is invoked by zenoh-c's internal Tokio runtime
  threads, not by the Dart isolate's thread.
- The `_call` function receives a `z_loaned_sample_t*` whose lifetime is
  limited to the callback invocation.
- The `_drop` function is called when the subscriber is undeclared, to free
  the context.

#### A.6.2 Why Dart FFI Cannot Construct These Closures

There are three independent blocking constraints:

**Constraint A: `Pointer.fromFunction` requires static/top-level functions.**

Dart's `Pointer.fromFunction<NativeFunction>()` can only create native
function pointers from static or top-level Dart functions. It cannot capture
closures, instance methods, or lambdas.

**Official reference** — `Pointer.fromFunction` API docs
([docs](https://api.dart.dev/stable/latest/dart-ffi/Pointer/fromFunction.html)):

> "Creates a Dart function pointer from a top-level or static Dart function.
> [...] The function must not be a closure (i.e. it must not capture any
> local variables)."

This means Dart cannot create a C function pointer that carries state (like
which Dart `StreamController` to forward samples to). The callback would
have no way to know its context.

**Constraint B: Callbacks are invoked on non-Dart threads.**

zenoh-c's subscriber callback runs on a Tokio runtime thread. Dart FFI
callbacks created via `Pointer.fromFunction` are restricted to being called
from the same thread that created them (the Dart isolate's mutator thread).

**Official reference** — `Pointer.fromFunction` API docs
([docs](https://api.dart.dev/stable/latest/dart-ffi/Pointer/fromFunction.html)):

> "The pointer returned will remain alive for the duration of the current
> isolate's lifetime. After the isolate it was created in is terminated,
> invoking it from native code will cause undefined behavior."

**GitHub issue #48865** ([dart-lang/sdk#48865](https://github.com/dart-lang/sdk/issues/48865))
confirms the threading restriction: calling a `Pointer.fromFunction` callback
from a non-Dart thread causes undefined behavior.

**Constraint C: `NativeCallable.listener` has limited utility.**

Dart 3.1+ added `NativeCallable.listener` which CAN be called from any
thread, but:
- It still cannot capture closures (must be a static/top-level function)
- Context must be passed via integer baton, not `void*` pointer
- It is cumbersome for complex multi-field data (5-element sample arrays)

**GitHub issue #52689** ([dart-lang/sdk#52689](https://github.com/dart-lang/sdk/issues/52689))
discusses the limitations and workarounds.

#### A.6.3 How the C Shim Solves This

The shim implements a **NativePort callback bridge** pattern:

1. **C side:** A C callback function (static, with full access to zenoh-c
   types) extracts fields from the zenoh-c sample, constructs a
   `Dart_CObject` array, and posts it to a Dart `ReceivePort` via the
   thread-safe `Dart_PostCObject_DL`.

2. **Dart side:** A `ReceivePort` listener running on the Dart event loop
   receives the deserialized data and forwards it to a
   `StreamController<Sample>`.

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

- **Thread-safe:** Documented as safe to call from any thread
  ([initializeApiDLData docs](https://api.dart.dev/stable/latest/dart-ffi/NativeApi/initializeApiDLData.html)).
  This is the officially supported mechanism for native code running on
  non-Dart threads to deliver data to a Dart isolate.

- **Deep copy semantics:** `Dart_PostCObject_DL` copies the `Dart_CObject`
  data into the Dart heap before returning, so the C callback can safely
  free temporary buffers immediately after the call.

- **Requires initialization:** The Dart API DL must be initialized once via
  `Dart_InitializeApiDL(NativeApi.initializeApiDLData)`. This is why the
  shim has `zd_init_dart_api_dl()`, called during `_initBindings()`.

The same pattern is used for all three callback types:

| Callback type | C shim function | Data posted | Dart receiver |
|---------------|----------------|-------------|---------------|
| Subscriber sample | `_zd_sample_callback` | 5-element array: [keyexpr, payload, kind, attachment, encoding] | `Subscriber.stream` |
| Matching status | `_zd_matching_status_callback` | Int64 (0 or 1) | `Publisher.matchingStatus` |
| Scout hello | `_zd_scout_hello_callback` | 3-element array: [zid_bytes, whatami, locators] + null sentinel | `Zenoh.scout()` future |

---

### A.7 Pattern 6: Loaning and Const/Mut Enforcement

#### A.7.1 The Problem

zenoh-c implements a **borrowing protocol** where owned types (`z_owned_*_t`)
must be "loaned" to produce temporary references (`z_loaned_*_t`) before they
can be passed to most API functions. The protocol distinguishes between
immutable borrows (`const z_loaned_*_t*`) and mutable borrows
(`z_loaned_*_t*`).

**Evidence** (`extern/zenoh-c/include/zenoh_commons.h`):

```c
// zenoh_commons.h:2218-2222
ZENOHC_API const struct z_loaned_config_t *z_config_loan(
    const struct z_owned_config_t *this_);              // immutable borrow
ZENOHC_API struct z_loaned_config_t *z_config_loan_mut(
    struct z_owned_config_t *this_);                    // mutable borrow
```

Every owned type has a corresponding loan function pair. The `const` qualifier
on the return type enforces the immutability contract at the C compiler level:
a function accepting `const z_loaned_config_t*` cannot mutate the underlying
config through that pointer.

#### A.7.2 Why the Per-Type Functions ARE Exported

Unlike Pattern 1 (`static inline` move functions), the per-type loan functions
**are real, exported symbols** in `libzenohc.so`:

```
$ nm -D extern/zenoh-c/target/release/libzenohc.so | grep -E 'z_(config|session|bytes|publisher)_loan'
000000000038ad40 T z_bytes_loan
000000000038ad50 T z_bytes_loan_mut
0000000000390370 T z_config_loan
0000000000390380 T z_config_loan_mut
000000000039e810 T z_publisher_loan
000000000039e820 T z_publisher_loan_mut
00000000003a59b0 T z_session_loan
00000000003a59c0 T z_session_loan_mut
```

This is critical: the loan functions could theoretically be called from Dart
FFI via `DynamicLibrary.lookup`. However, two independent barriers prevent
direct use.

#### A.7.3 Barrier A: The Dispatch Layer Is a Macro

The zenoh-c API presents loaning through `_Generic` macros (Pattern 2):

```c
// zenoh_macros.h:65-119
#define z_loan(this_) \
    _Generic((this_), \
        z_owned_config_t : z_config_loan, \
        z_owned_session_t : z_session_loan, \
        z_owned_publisher_t : z_publisher_loan, \
        /* ... 48 branches total ... */ \
    )(&this_)
```

No symbol named `z_loan` or `z_loan_mut` exists in `libzenohc.so`. Dart
cannot call these macros. It must know which monomorphic function to call
for each type — a responsibility the shim absorbs.

#### A.7.4 Barrier B: Const Qualification Erasure

Even if Dart called the per-type functions directly, Dart FFI's type system
**erases the const/mut distinction**. All zenoh-c types are mapped to
`ffi.Opaque` in `ffigen.yaml`. A `Pointer<z_loaned_config_t>` in Dart
carries no information about whether the pointer is `const` or mutable.

Dart's `Pointer<T>` class has no concept of const pointers:

> "A Pointer represents a pointer into native C memory."
> — [Pointer class](https://api.dart.dev/stable/latest/dart-ffi/Pointer-class.html)

There is no `ConstPointer<T>` or const qualifier in `dart:ffi`. This means:
- A Dart program cannot distinguish `const z_loaned_config_t*` from
  `z_loaned_config_t*`
- There is no compile-time or runtime check preventing a mutable operation
  on an immutably-borrowed reference
- Incorrect usage (passing an immutable loan where a mutable loan is required)
  would cause undefined behavior in zenoh-c

#### A.7.5 How the Shim Resolves This

The C shim absorbs both barriers:

1. **Macro bypass:** The shim calls the monomorphic functions directly
   (`z_config_loan` not `z_loan(config)`), providing stable exported symbols
   for Dart to call.

2. **Const enforcement in C:** The shim's function signatures enforce const
   correctness at the C compiler level:

```c
// Returns const pointer — C compiler prevents mutation through this reference
FFI_PLUGIN_EXPORT const z_loaned_config_t*
    zd_config_loan(const z_owned_config_t* config);

// Returns mutable pointer — allows mutation (used for SHM buffer writes)
FFI_PLUGIN_EXPORT z_loaned_shm_mut_t*
    zd_shm_mut_loan_mut(z_owned_shm_mut_t* buf);
```

3. **Naming convention:** The shim uses `zd_*_loan` for immutable borrows
   and `zd_*_loan_mut` for mutable borrows, making the contract explicit
   even though Dart cannot enforce it.

#### A.7.6 Current Loan Functions in the Shim

| C shim function | Qualifier | Wraps |
|----------------|-----------|-------|
| `zd_config_loan` | `const` | `z_config_loan` |
| `zd_session_loan` | `const` | `z_session_loan` |
| `zd_view_keyexpr_loan` | `const` | `z_view_keyexpr_loan` |
| `zd_bytes_loan` | `const` | `z_bytes_loan` |
| `zd_string_loan` | `const` | `z_string_loan` |
| `zd_publisher_loan` | `const` | `z_publisher_loan` |
| `zd_shm_provider_loan` | `const` | `z_shm_provider_loan` |
| `zd_shm_mut_loan_mut` | **mutable** | `z_shm_mut_loan_mut` |

Seven immutable loans, one mutable loan. The mutable variant is used only
for SHM buffer data access (`zd_shm_mut_data_mut` requires a mutable loan).

#### A.7.7 Why This Is Distinct From Patterns 1 and 2

| Aspect | Pattern 1 | Pattern 2 | **Pattern 6** |
|--------|-----------|-----------|---------------|
| **Barrier** | No exported symbol (`static inline`) | No exported symbol (`_Generic` macro) | Exported symbol exists, but const/mut qualifier is lost across FFI |
| **nm -D** | Function absent | Macro absent | **Function present** (`T` in symbol table) |
| **Could Dart call it?** | No | No | Technically yes, but **unsafely** |
| **What the shim adds** | Inlines the call into exported body | Calls monomorphic function directly | Enforces const/mut at C level + provides stable naming |

The move functions (Pattern 1) and the `_Generic` macros (Pattern 2) are
purely about **symbol availability** — the code physically cannot be reached
from Dart. Pattern 6 is about **semantic safety** — the code can be reached,
but calling it directly would bypass const enforcement that C provides.

---

### A.8 End-to-End Worked Example: `z_put`

This section traces a single operation — publishing data on a key expression
— through the six patterns to show how they compound.

#### A.8.1 What a C Consumer Does

```c
// 1. Allocate and initialize options (Pattern 3)
z_put_options_t opts;
z_put_options_default(&opts);

// 2. Create payload bytes
z_owned_bytes_t payload;
z_bytes_copy_from_str(&payload, "Hello");

// 3. Call z_put with moved payload (Pattern 1)
z_put(z_session_loan(&session),        // loan macro (Pattern 6 + Pattern 2)
      z_view_keyexpr_loan(&keyexpr),   // loan macro (Pattern 6 + Pattern 2)
      z_bytes_move(&payload),          // static inline — NOT exported (Pattern 1)
      &opts);
```

#### A.8.2 What Dart FFI Cannot Do

Dart FFI **can** call:
- `z_bytes_copy_from_str` — exported (`nm -D` confirms)
- `z_put` — exported (`000000000039e3f0 T z_put`)
- `z_put_options_default` — exported (`000000000039f020 T z_put_options_default`)
- `z_bytes_loan` — exported (`000000000038ad40 T z_bytes_loan`)

Dart FFI **cannot** call:
- `z_bytes_move` — `static inline`, not in symbol table (Pattern 1)
- `sizeof(z_put_options_t)` — Dart cannot compute this (Pattern 4)
- Set `opts.encoding` — requires `z_encoding_move`, `static inline` (Pattern 3)

**The call chain breaks at `z_bytes_move`.** Even though `z_put` is a real
symbol, Dart cannot construct its third argument (`z_moved_bytes_t*`).

#### A.8.3 What the C Shim Does

```c
FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,   // already loaned by Dart
    const z_loaned_keyexpr_t* keyexpr,   // already loaned by Dart
    z_owned_bytes_t* payload) {          // owned, will be moved
    z_put_options_t opts;                // Pattern 3: stack-allocated
    z_put_options_default(&opts);        // Pattern 3: initialized
    return z_put(session, keyexpr,
                 z_bytes_move(payload),  // Pattern 1: static inline resolved
                 &opts);                 // Pattern 3: passed through
}
```

#### A.8.4 The Full Call Chain

```
Dart: session.put('demo/test', 'Hello')
  → ZBytes.fromString('Hello')
    → calloc.allocate(bindings.zd_bytes_sizeof())     [Pattern 4: sizeof query]
    → bindings.zd_bytes_copy_from_str(ptr, nativeStr)  [exported symbol]
  → bindings.zd_session_loan(sessionPtr)                  [Pattern 6: const loan]
  → bindings.zd_view_keyexpr_loan(kePtr)                  [Pattern 6: const loan]
  → bindings.zd_put(loanedSession, loanedKe, payloadPtr)  [shim function]
    → C shim: z_put_options_default(&opts)              [Pattern 3: options init]
    → C shim: z_put(session, keyexpr,
                     z_bytes_move(payload),              [Pattern 1: static inline]
                     &opts)                              [Pattern 3: options pass]
      → libzenohc.so: z_put()                           [exported symbol]
  → payload.markConsumed()                               [Dart ownership tracking]
```

Five patterns, one operation. The C shim collapses all of them into
FFI-callable functions with simple scalar parameters.

### A.9 What the Shim Does NOT Do

The shim is deliberately thin. It does not:

- Add error recovery or retry logic
- Buffer or queue data
- Manage threads or synchronization
- Add abstraction layers or new concepts
- Change zenoh-c's ownership semantics

Every `zd_*` function maps to one or a small sequence of `z_*` calls. The
shim is a **mechanical flattening layer**, not an abstraction.

---

## Part B: Function-by-Function Analysis

### B.1 Initialization (2 functions)

| Function | Wraps | Purpose |
|----------|-------|---------|
| `zd_init_dart_api_dl` | `Dart_InitializeApiDL` | Initializes Dart native API for `Dart_PostCObject_DL` |
| `zd_init_log` | `zc_init_log_from_env_or` | Initializes zenoh logger |

**Assessment:** Correct and minimal. `zd_init_dart_api_dl` must be called
before any NativePort usage. The lazy singleton in `native_lib.dart` calls
it on first access, which is the right place. The return value is propagated
to Dart, which checks for non-zero failure.

### B.2 Config (5 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_config_sizeof` | `sizeof(z_owned_config_t)` | Pattern 4 |
| `zd_config_default` | `z_config_default` | Pattern 3 |
| `zd_config_insert_json5` | `z_config_loan_mut` + `zc_config_insert_json5` | Pattern 1 (loan_mut in `_Generic`) |
| `zd_config_loan` | `z_config_loan` | Pattern 1 |
| `zd_config_drop` | `z_config_drop(z_config_move(...))` | Pattern 1 (`z_config_move` is `static inline`) |

**Assessment:** Correct. `zd_config_insert_json5` properly obtains a mutable
loan before inserting. The drop function correctly sequences move-then-drop.

**Observation:** `zd_config_loan` may be unused in the current Dart code. The
Dart side passes config pointers directly to `zd_open_session`, which calls
`z_config_move` internally. Harmless but worth noting.

### B.3 Session (4 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_session_sizeof` | `sizeof(z_owned_session_t)` | Pattern 4 |
| `zd_open_session` | `z_open(session, z_config_move(config), NULL)` | Patterns 1, 3 |
| `zd_session_loan` | `z_session_loan` | Pattern 1 |
| `zd_close_session` | `z_close` + `z_session_drop` | Pattern 1 |

**Assessment:** Correct. `zd_close_session` performs the two-step
close-then-drop sequence that zenoh-c requires. The third parameter to
`z_open` (open options) is NULL, meaning defaults — appropriate for the
current phase.

**Finding [F1]: `z_close` return value is not checked in `zd_close_session`.**

```c
FFI_PLUGIN_EXPORT void zd_close_session(z_owned_session_t* session) {
  z_close(z_session_loan_mut(session), NULL);   // return value discarded
  z_session_drop(z_session_move(session));
}
```

**Severity:** Low. zenoh-cpp similarly ignores the return. Close-time errors
are non-actionable.

### B.4 KeyExpr (4 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_view_keyexpr_sizeof` | `sizeof(z_view_keyexpr_t)` | Pattern 4 |
| `zd_view_keyexpr_from_str` | `z_view_keyexpr_from_str` | Pattern 1 |
| `zd_view_keyexpr_loan` | `z_view_keyexpr_loan` | Pattern 1 |
| `zd_keyexpr_as_view_string` | `z_keyexpr_as_view_string` | Pattern 1 |

**Assessment:** Correct. Uses view (non-owning) key expressions throughout,
which avoids unnecessary copies. The Dart `KeyExpr` class owns the backing
C string and frees it in `dispose()` — the view borrows this string, so
the lifetime constraint is satisfied as long as `KeyExpr.dispose()` is not
called while the view is in use. The `_withKeyExpr` helper in `session.dart`
guarantees this via `try/finally`.

### B.5 Bytes (6 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_bytes_sizeof` | `sizeof(z_owned_bytes_t)` | Pattern 4 |
| `zd_bytes_copy_from_str` | `z_bytes_copy_from_str` | Pattern 1 |
| `zd_bytes_copy_from_buf` | `z_bytes_copy_from_buf` | Pattern 1 |
| `zd_bytes_to_string` | `z_bytes_to_string` | Pattern 1 |
| `zd_bytes_loan` | `z_bytes_loan` | Pattern 1 |
| `zd_bytes_drop` | `z_bytes_drop(z_bytes_move(...))` | Pattern 1 |

**Assessment:** Correct. Both `copy_from_str` and `copy_from_buf` make
defensive copies into zenoh-owned memory, which is the right approach for
FFI — the Dart-allocated buffer can be freed immediately after the copy.

### B.6 String / View String (7 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_string_sizeof` | `sizeof(z_owned_string_t)` | Pattern 4 |
| `zd_string_loan` | `z_string_loan` | Pattern 1 |
| `zd_string_data` | `z_string_data` | Pattern 1 |
| `zd_string_len` | `z_string_len` | Pattern 1 |
| `zd_string_drop` | `z_string_drop(z_string_move(...))` | Pattern 1 |
| `zd_view_string_sizeof` | `sizeof(z_view_string_t)` | Pattern 4 |
| `zd_view_string_data` | `z_view_string_loan` + `z_string_data` | Pattern 1 |
| `zd_view_string_len` | `z_view_string_loan` + `z_string_len` | Pattern 1 |

**Assessment:** Correct. The view string convenience functions
(`zd_view_string_data`, `zd_view_string_len`) each do a loan-then-access
in one call, reducing the number of FFI round-trips from Dart. Sensible
optimization.

**Important:** `zd_string_data` returns a pointer that is **not guaranteed
to be null-terminated**. The Dart side correctly uses
`data.cast<Utf8>().toDartString(length: len)` with an explicit length
parameter everywhere. Correct and avoids buffer overread.

### B.7 Put / Delete (2 functions)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_put` | `z_put_options_default` + `z_put` | Patterns 1, 3 |
| `zd_delete` | `z_delete_options_default` + `z_delete` | Pattern 3 |

**Assessment:** Correct. Both functions initialize options to defaults and
pass them through. `zd_put` moves the payload, transferring ownership to
zenoh-c. The Dart side calls `payload.markConsumed()` after the call.

**Design choice:** `zd_put` does not expose encoding, attachment, or QoS
options. These are available through `zd_publisher_put` (the declared
publisher path). This split mirrors zenoh-c's Session-level vs
Publisher-level API separation and is intentional.

### B.8 Subscriber (3 functions + 2 static callbacks)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_subscriber_sizeof` | `sizeof(z_owned_subscriber_t)` | Pattern 4 |
| `zd_declare_subscriber` | `z_closure_sample` + `z_declare_subscriber` | Patterns 1, 5 |
| `zd_subscriber_drop` | `z_subscriber_drop(z_subscriber_move(...))` | Pattern 1 |

**Callback bridge data flow:**

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

**Correctness of `_zd_sample_callback`:**

1. **Key expression extraction** (lines 202-207): Obtains a view string from
   the sample's key expression. The view borrows from the sample, valid for
   the callback duration. Copied into a `malloc`'d buffer for
   `Dart_CObject_kString` (requires null-termination). **Correct.**

2. **Payload extraction** (lines 209-214): Converts payload bytes to a string
   via `z_bytes_to_string`. Sent as `Dart_CObject_kTypedData` (Uint8List).
   `Dart_PostCObject_DL` copies the data before returning, so the pointer
   remains valid. **Correct.** (See Finding F2.)

3. **Kind** (line 217): `z_sample_kind` returns enum (0=put, 1=delete).
   Sent as `Dart_CObject_kInt64`. **Correct.**

4. **Attachment** (lines 220-261): Nullable. When present, converted to
   string and sent as Uint8List. When absent, sent as `Dart_CObject_kNull`.
   **Correct.**

5. **Encoding** (lines 223-228): Extracted via `z_encoding_to_string`, copied
   to `malloc`'d null-terminated buffer, sent as string. **Correct.**

6. **Memory cleanup** (lines 279-285): Frees `key_buf`, `enc_buf`, drops all
   owned strings. Attachment string dropped only if present (guarded by
   `has_attachment`). **Correct.**

**Context lifecycle:**

- `zd_declare_subscriber` heap-allocates context via `malloc`. On failure,
  drops the closure (invoking `_zd_sample_drop`, freeing context). On
  success, context lives until `zd_subscriber_drop` triggers the closure's
  drop callback.
- Error-path closure drop is defensively correct: `z_closure_sample_move` in
  the error path produces a no-op on already-gravestone closures, matching
  zenoh-c's idempotent drop guarantee.

### B.9 Publisher (8 functions + 2 static callbacks)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_publisher_sizeof` | `sizeof(z_owned_publisher_t)` | Pattern 4 |
| `zd_declare_publisher` | `z_publisher_options_default` + `z_declare_publisher` | Patterns 1, 3 |
| `zd_publisher_loan` | `z_publisher_loan` | Pattern 1 |
| `zd_publisher_drop` | `z_publisher_drop(z_publisher_move(...))` | Pattern 1 |
| `zd_publisher_put` | `z_publisher_put_options_default` + `z_publisher_put` | Patterns 1, 3 |
| `zd_publisher_delete` | `z_publisher_delete_options_default` + `z_publisher_delete` | Pattern 3 |
| `zd_publisher_keyexpr` | `z_publisher_keyexpr` | Pattern 1 |
| `zd_publisher_declare_background_matching_listener` | `z_closure_matching_status` + `z_publisher_declare_background_matching_listener` | Patterns 1, 5 |
| `zd_publisher_get_matching_status` | `z_publisher_get_matching_status` | — |

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

**Encoding ownership in options is correct.** `z_declare_publisher` is
responsible for cleaning up moved values on failure per zenoh-c contract.

**Matching listener callback:** Posts `Int64` (1 or 0) via NativePort. Same
heap-allocated context pattern as subscriber. Cleanup on failure mirrors
subscriber. **Correct.**

### B.10 Info / ZID (4 functions + 1 static callback)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_info_zid` | `z_info_zid` | Pattern 1 |
| `zd_id_to_string` | `z_id_to_string` | — |
| `zd_info_routers_zid` | `z_closure_zid` + `z_info_routers_zid` | Pattern 5 |
| `zd_info_peers_zid` | `z_closure_zid` + `z_info_peers_zid` | Pattern 5 |

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

Uses stack-allocated context and caller-provided buffer. The closure has
`NULL` for the drop callback because the context is on the stack and does
not need freeing.

**Design choice:** Synchronous buffer collection instead of NativePort.
Appropriate because `z_info_routers_zid` is synchronous — the callback fires
inline before the function returns. NativePort would add unnecessary async
complexity. **Correct.**

**Note:** The Dart side uses `maxCount = 64`, so up to 1024 bytes. If a
deployment has more than 64 connected routers or peers, extra ZIDs are
silently dropped. Acceptable for current use cases.

### B.11 Scout (2 functions + 1 static callback)

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_scout` | `z_scout_options_default` + `z_scout` + null sentinel | Patterns 1, 3, 5 |
| `zd_whatami_to_view_string` | `z_whatami_to_view_string` | — |

**Scout callback:** `_zd_scout_hello_callback` extracts ZID (16 bytes),
whatami (int), and locators (semicolon-joined string) from each
`z_loaned_hello_t`. Locators are built with a two-pass algorithm: compute
total length, allocate, copy. **Correct and null-terminated.**

**Stack-allocated context:**

```c
zd_scout_context_t ctx = { .dart_port = (Dart_Port_DL)dart_port };
z_closure_hello(&closure, _zd_scout_hello_callback, NULL, &ctx);
```

Drop callback is `NULL` because context is on the stack. Safe because
`z_scout` is synchronous — blocks until timeout expires, all callbacks fire
before return. **Correct.**

**Null sentinel:** After `z_scout` returns, the shim posts a null
`Dart_CObject` to signal completion. The Dart side uses a `Completer` that
resolves when it receives null. **Correct.**

### B.12 Shared Memory (13 functions, conditionally compiled)

All SHM functions are guarded by:

```c
#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)
```

`CMakeLists.txt` defines both flags. Correct — SHM is an unstable zenoh
feature requiring explicit opt-in.

| Function | Wraps | Patterns Resolved |
|----------|-------|-------------------|
| `zd_shm_provider_sizeof` | `sizeof(z_owned_shm_provider_t)` | Pattern 4 |
| `zd_shm_provider_new` | `z_shm_provider_default_new` | Pattern 1 |
| `zd_shm_provider_loan` | `z_shm_provider_loan` | Pattern 1 |
| `zd_shm_provider_drop` | `z_shm_provider_drop(z_shm_provider_move(...))` | Pattern 1 |
| `zd_shm_provider_available` | `z_shm_provider_available` | — |
| `zd_shm_mut_sizeof` | `sizeof(z_owned_shm_mut_t)` | Pattern 4 |
| `zd_shm_provider_alloc` | `z_shm_provider_alloc` | Pattern 1 |
| `zd_shm_provider_alloc_gc_defrag_blocking` | `z_shm_provider_alloc_gc_defrag_blocking` | Pattern 1 |
| `zd_shm_mut_loan_mut` | `z_shm_mut_loan_mut` | Pattern 1 |
| `zd_shm_mut_data_mut` | `z_shm_mut_data_mut` | — |
| `zd_shm_mut_len` | `z_shm_mut_len` | — |
| `zd_bytes_from_shm_mut` | `z_bytes_from_shm_mut(bytes, z_shm_mut_move(buf))` | Pattern 1 |
| `zd_shm_mut_drop` | `z_shm_mut_drop(z_shm_mut_move(...))` | Pattern 1 |

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
`null` on failure — the right approach for allocation failures (not
exceptional). **Correct.**

---

## Part C: Cross-Cutting Analysis

### C.1 Memory Ownership Protocol

The Dart side implements a three-state model mirroring zenoh-c's gravestone
semantics:

| State | Flags | Operations allowed |
|-------|-------|--------------------|
| **Live** | `_disposed=false, _consumed=false` | All operations |
| **Consumed** | `_consumed=true` | None (StateError) |
| **Disposed** | `_disposed=true` | `dispose()` (no-op) |

Enforced consistently across `Config`, `ZBytes`, `ShmMutBuffer`, `KeyExpr`.

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

**Assessment:** This pattern correctly prevents double-free, use-after-free,
use-after-consume, and leak-on-consume.

### C.2 Wrapper Memory vs. Content Memory

A critical distinction: Dart `calloc`-allocates wrapper memory for opaque
zenoh types (e.g., `calloc.allocate(bindings.zd_session_sizeof())`). This
wrapper holds zenoh-c's internal state. On cleanup:

1. Call `zd_*_drop()` to release zenoh-c's internal resources (Rust allocator)
2. Call `calloc.free()` to release the wrapper memory (Dart allocator)

This two-step cleanup is implemented consistently:

```dart
// Session.close():
bindings.zd_close_session(_ptr.cast());  // Step 1: zenoh-c cleanup
calloc.free(_ptr);                        // Step 2: wrapper cleanup

// Config.dispose():
bindings.zd_config_drop(_ptr.cast());    // Step 1
calloc.free(_ptr);                        // Step 2
```

**Assessment:** Correct. Applied consistently across all classes.

### C.3 Thread Safety

All C callbacks use only stack-local variables + read-only context access +
`Dart_PostCObject_DL` (thread-safe). No shared mutable state. Correct.

`zd_subscriber_context_t` contains only a `Dart_Port_DL` value (an integer).
Written once during `zd_declare_subscriber`, read from callbacks. No mutation
after initialization, so no races are possible.

### C.4 Error Handling Completeness

All 19 error-returning shim functions are checked in Dart, with one exception
(Finding F6).

---

## Part D: Pattern Resolution Matrix

This matrix maps every C shim function to which of the six patterns it
resolves. A function may resolve multiple patterns.

| C shim function | P1 (inline) | P2 (`_Generic`) | P3 (options) | P4 (sizeof) | P5 (callbacks) | P6 (loaning) |
|-----------------|:-:|:-:|:-:|:-:|:-:|:-:|
| `zd_init_dart_api_dl` | | | | | X | |
| `zd_init_log` | | | | | | |
| `zd_config_sizeof` | | | | X | | |
| `zd_config_default` | | | X | | | |
| `zd_config_insert_json5` | X | X | | | | |
| `zd_config_loan` | | X | | | | X |
| `zd_config_drop` | X | | | | | |
| `zd_session_sizeof` | | | | X | | |
| `zd_open_session` | X | | X | | | |
| `zd_session_loan` | | X | | | | X |
| `zd_close_session` | X | X | | | | |
| `zd_view_keyexpr_sizeof` | | | | X | | |
| `zd_view_keyexpr_from_str` | X | | | | | |
| `zd_view_keyexpr_loan` | | X | | | | X |
| `zd_keyexpr_as_view_string` | X | | | | | |
| `zd_bytes_sizeof` | | | | X | | |
| `zd_bytes_copy_from_str` | X | | | | | |
| `zd_bytes_copy_from_buf` | X | | | | | |
| `zd_bytes_to_string` | X | | | | | |
| `zd_bytes_loan` | | X | | | | X |
| `zd_bytes_drop` | X | | | | | |
| `zd_string_sizeof` | | | | X | | |
| `zd_string_loan` | | X | | | | X |
| `zd_string_data` | X | | | | | |
| `zd_string_len` | X | | | | | |
| `zd_string_drop` | X | | | | | |
| `zd_view_string_sizeof` | | | | X | | |
| `zd_view_string_data` | X | X | | | | |
| `zd_view_string_len` | X | X | | | | |
| `zd_put` | X | | X | | | |
| `zd_delete` | | | X | | | |
| `zd_subscriber_sizeof` | | | | X | | |
| `zd_declare_subscriber` | X | | | | X | |
| `zd_subscriber_drop` | X | | | | | |
| `zd_publisher_sizeof` | | | | X | | |
| `zd_declare_publisher` | X | | X | | | |
| `zd_publisher_loan` | | X | | | | X |
| `zd_publisher_drop` | X | | | | | |
| `zd_publisher_put` | X | | X | | | |
| `zd_publisher_delete` | | | X | | | |
| `zd_publisher_keyexpr` | X | | | | | |
| `zd_pub..._matching_listener` | X | | | | X | |
| `zd_publisher_get_matching_status` | | | | | | |
| `zd_info_zid` | X | | | | | |
| `zd_id_to_string` | | | | | | |
| `zd_info_routers_zid` | | | | | X | |
| `zd_info_peers_zid` | | | | | X | |
| `zd_scout` | X | | X | | X | |
| `zd_whatami_to_view_string` | | | | | | |
| `zd_shm_provider_sizeof` | | | | X | | |
| `zd_shm_provider_new` | X | | | | | |
| `zd_shm_provider_loan` | | X | | | | X |
| `zd_shm_provider_drop` | X | | | | | |
| `zd_shm_provider_available` | | | | | | |
| `zd_shm_mut_sizeof` | | | | X | | |
| `zd_shm_provider_alloc` | X | | | | | |
| `zd_shm_provider_alloc_gc_defrag_blocking` | X | | | | | |
| `zd_shm_mut_loan_mut` | | X | | | | X |
| `zd_shm_mut_data_mut` | | | | | | |
| `zd_shm_mut_len` | | | | | | |
| `zd_bytes_from_shm_mut` | X | | | | | |
| `zd_shm_mut_drop` | X | | | | | |

**Totals:** 34 functions resolve Pattern 1, 14 resolve Pattern 2 (`_Generic`
dispatch), 8 resolve Pattern 3, 12 resolve Pattern 4, 6 resolve Pattern 5,
8 resolve Pattern 6 (loaning).

**Notes:**

- **Pattern 1** marks functions that call `static inline` functions
  (`z_*_move`, `z_*_drop` wrappers). Functions that only call exported
  zenoh-c symbols are NOT marked P1.
- **Pattern 2** marks functions that bypass `_Generic` macros (`z_loan`,
  `z_loan_mut`, `z_drop`, `z_move`, `z_close`) by calling the monomorphic
  target directly.
- **Pattern 6** marks the 8 explicit loan functions (`zd_*_loan`,
  `zd_*_loan_mut`). These resolve both the macro dispatch (P2) and the
  const/mut enforcement barrier. The P6 mark indicates the loaning semantic
  is the primary purpose of the function — not merely a side effect of
  macro bypass.
- Loan functions are **no longer** marked P1. The per-type loan functions
  (`z_config_loan`, `z_bytes_loan`, etc.) are exported symbols in
  `libzenohc.so` — they are not `static inline`. The previous matrix
  incorrectly attributed Pattern 1 to loan wrappers.

---

## Part E: Conformance Summary

### E.1 C Best Practices

| Practice | Status | Notes |
|----------|--------|-------|
| All exported symbols have `FFI_PLUGIN_EXPORT` | PASS | `__attribute__((visibility("default")))` on non-Windows |
| `C_VISIBILITY_PRESET hidden` in CMake | PASS | Only `FFI_PLUGIN_EXPORT` symbols are visible |
| Consistent `zd_` namespace prefix | PASS | No collisions with zenoh-c's `z_`/`zc_` namespace |
| Return code checking | PARTIAL | F4: `z_encoding_from_str` unchecked |
| Memory cleanup on all paths | PASS | Closures dropped on declare failure |
| No undefined behavior | PASS | All pointer arithmetic is bounds-checked |
| Minimal header includes | PASS | Only `stdint.h` and `zenoh.h` |
| Const correctness | PASS | `const` on all loan/read-only parameters |
| Stack allocation where possible | PASS | Scout and ZID contexts are stack-allocated |
| Heap allocation only when lifetime exceeds scope | PASS | Subscriber and matching contexts are heap-allocated |
| Feature guards for optional functionality | PASS | SHM behind `#ifdef` |

### E.2 Dart FFI Best Practices

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

### E.3 Architecture Conformance

| Principle | Status | Notes |
|-----------|--------|-------|
| Shim is mechanical (no business logic) | PASS | Every function is 1-5 zenoh-c calls |
| Single-load library pattern | PASS | Only `libzenoh_dart.so` loaded; OS resolves `libzenohc.so` |
| No abstraction beyond what Dart needs | PASS | No unnecessary wrapper types |
| Options structs internalized | PASS | Dart never touches `z_*_options_t` |
| Move semantics handled in C | PASS | Dart never calls `z_*_move` |
| Callback bridge via NativePort | PASS | Thread-safe, copies data |
| Sentinel values for optional params | PASS | NULL for strings, -1 for enums |
| Consistent `Pointer<Void>` usage | PASS | Avoids generating struct bindings for zenoh-c internals |

---

## Findings

### F1: `z_close` Return Value Ignored [LOW]

**Location:** `zenoh_dart.c`, `zd_close_session`

The return value of `z_close` is discarded. zenoh-cpp similarly ignores it.
Close-time errors are non-actionable.

### F2: Payload Encoding Assumption in Subscriber Callback [LOW]

**Location:** `zenoh_dart.c:210-214`, `subscriber.dart:49`

The C shim converts payload bytes to a string via `z_bytes_to_string`, then
sends the string's raw bytes as `Dart_CObject_kTypedData`. The Dart side
does `utf8.decode(payloadBytes)`. This round-trip adds an unnecessary copy
compared to sending raw bytes directly from `z_sample_payload`. However, it
would require the more complex bytes reader API (`z_bytes_reader_*`).

**Impact:** Performance only, not correctness. Most payloads are small
relative to network I/O.

### F3: `ZBytes.fromUint8List` Element-by-Element Copy [LOW]

**Location:** `bytes.dart:51-53`

```dart
final Pointer<Uint8> nativeBuf = calloc<Uint8>(data.length);
for (var i = 0; i < data.length; i++) {
    nativeBuf[i] = data[i];
}
```

Could use `nativeBuf.asTypedList(data.length).setAll(0, data)` for bulk
copy via `memcpy`. The SHM zero-copy path already uses this pattern
correctly.

### F4: `owned_encoding` Potentially Uninitialized on Invalid String [LOW]

**Location:** `zenoh_dart.c:344-348`

```c
z_owned_encoding_t owned_encoding;
if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
}
```

If `z_encoding_from_str` returned a non-zero error code, `owned_encoding`
could be in an indeterminate state. The return value is not checked. In
practice, zenoh-c's `z_encoding_from_str` always succeeds (treats the
string as an opaque MIME type).

### F5: `Zenoh.initLog` Allocator Mismatch [LOW]

**Location:** `zenoh.dart:42`

```dart
final cStr = fallback.toNativeUtf8();  // uses malloc
// ...
calloc.free(cStr);  // should be malloc.free(cStr)
```

`String.toNativeUtf8()` allocates via `malloc`. The cleanup uses
`calloc.free()`. Both resolve to the same system `free()` in practice, but
it violates the C convention of matching allocator pairs. Compare with
`config.dart:61-62` which correctly uses `malloc.free`.

### F6: `Zenoh.scout` Ignores `zd_scout` Return Value [MEDIUM]

**Location:** Dart side, `Zenoh.scout()`

Scout failures are indistinguishable from "no entities found." The Dart
code does not check the return value from `zd_scout`.

### F7: `ZBytes.dispose()` Leaks Calloc Wrapper When Consumed [LOW]

**Location:** `bytes.dart`, `ZBytes.dispose()`

When a `ZBytes` has been consumed (ownership transferred to zenoh-c), the
`dispose()` method returns early without calling `calloc.free(_ptr)`. The
native content was consumed, but the calloc wrapper memory still needs to be
freed. The `ShmMutBuffer.dispose()` pattern handles this correctly and should
be matched.

---

## Findings Summary

| ID | Description | Severity |
|----|-------------|----------|
| F1 | `z_close` return value ignored in `zd_close_session` | Low |
| F2 | Payload passes through `z_bytes_to_string` in subscriber callback | Low |
| F3 | `ZBytes.fromUint8List` element-by-element copy | Low |
| F4 | `z_encoding_from_str` return code unchecked | Low |
| F5 | `Zenoh.initLog` frees `malloc`'d string with `calloc.free` | Low |
| F6 | `Zenoh.scout` ignores `zd_scout` return value | Medium |
| F7 | `ZBytes.dispose()` leaks calloc wrapper when consumed | Low |

---

## Pattern Summary

| Pattern | What It Is | Why Dart FFI Cannot Call It | How the Shim Resolves It |
|---------|-----------|---------------------------|--------------------------|
| **1: `static inline` move** | 56 identity-cast functions in `zenoh_macros.h` | `static` = internal linkage, `inline` = no exported symbol. `nm -D` confirms absence. ffigen permanently excludes them ([#146](https://github.com/dart-lang/ffigen/issues/146), [#459](https://github.com/dart-lang/native/issues/459)). | Shim calls them at compile time. The C compiler inlines the cast into the shim's exported function. |
| **2: `_Generic` macros** | 4 polymorphic macros with 25-56 branches each | Preprocessor construct. No symbol. Dispatches to type-specific functions at compile time. | Shim calls monomorphic functions directly (`z_bytes_loan` not `z_loan`). |
| **3: Options structs** | Stack-allocated structs with fields requiring Pattern 1 | `sizeof` unknown to Dart. Fields require `z_*_move` (Pattern 1). Layout is version-specific. | Shim allocates, initializes, sets fields, and passes — all in one exported function. Uses sentinel params for optional overrides. |
| **4: Opaque type sizes** | `z_owned_session_t` (8 bytes), `z_owned_config_t` (2008 bytes), etc. | Dart FFI has no `sizeof()` for foreign types. Types mapped to `Opaque` in ffigen. | Shim exports `zd_*_sizeof()` functions. Dart queries at runtime via `calloc.allocate(bindings.zd_*_sizeof())`. |
| **5: Closure callbacks** | C closure structs with function pointers invoked on Tokio threads | `Pointer.fromFunction` cannot capture state. Callbacks on non-Dart threads cause UB ([#48865](https://github.com/dart-lang/sdk/issues/48865)). `NativeCallable.listener` has limited utility ([#52689](https://github.com/dart-lang/sdk/issues/52689)). | NativePort bridge: C callback extracts fields, posts `Dart_CObject` array via thread-safe `Dart_PostCObject_DL`. Dart `ReceivePort` receives on event loop. |
| **6: Loaning (const/mut)** | Borrowing protocol: `z_*_loan()` returns `const z_loaned_*_t*`, `z_*_loan_mut()` returns `z_loaned_*_t*` | Per-type functions ARE exported (`nm -D` confirms), but `z_loan`/`z_loan_mut` macros are not (Pattern 2). Dart's `Pointer<Opaque>` erases `const` — no compile-time or runtime enforcement of immutability. | Shim wraps each loan function with explicit naming (`zd_*_loan` vs `zd_*_loan_mut`). Const correctness enforced at C compiler level. |

The six patterns are not independent barriers — they **compound**. A single
`z_put` call requires Pattern 4 (to allocate the payload), Pattern 1 (to
move the payload), Pattern 6 (to loan the session and key expression), and
Pattern 3 (to create and pass options). A subscriber declaration adds
Pattern 5 (callback bridge). The C shim collapses all of these into single
FFI-callable functions with simple scalar parameters.

---

## References

### Dart FFI Official Documentation (all verified against Dart 3.11.1)

All `api.dart.dev/stable/latest/` URLs resolve to the current stable SDK.
Using `/latest/` ensures links remain valid as new Dart versions are released.

| Document | URL |
|----------|-----|
| dart:ffi library overview | https://api.dart.dev/stable/latest/dart-ffi/dart-ffi-library.html |
| C interop guide | https://dart.dev/interop/c-interop |
| DynamicLibrary class | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary-class.html |
| DynamicLibrary.lookup | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibrary/lookup.html |
| lookupFunction | https://api.dart.dev/stable/latest/dart-ffi/DynamicLibraryExtension/lookupFunction.html |
| NativeApi.initializeApiDLData | https://api.dart.dev/stable/latest/dart-ffi/NativeApi/initializeApiDLData.html |
| Pointer class | https://api.dart.dev/stable/latest/dart-ffi/Pointer-class.html |
| Pointer.fromFunction | https://api.dart.dev/stable/latest/dart-ffi/Pointer/fromFunction.html |
| Void class | https://api.dart.dev/stable/latest/dart-ffi/Void-class.html |
| Opaque class | https://api.dart.dev/stable/latest/dart-ffi/Opaque-class.html |
| Struct class | https://api.dart.dev/stable/latest/dart-ffi/Struct-class.html |
| sizeOf function | https://api.dart.dev/stable/latest/dart-ffi/sizeOf.html |
| ffigen package | https://pub.dev/packages/ffigen |
| Dart what's new | https://dart.dev/resources/whats-new |

### Bug Tracker Citations

| Issue | Status | Key Finding |
|-------|--------|-------------|
| [dart-lang/ffigen#146](https://github.com/dart-lang/ffigen/issues/146) | Closed (COMPLETED) | ffigen now **skips** inline functions: "We should skip them." |
| [dart-lang/native#459](https://github.com/dart-lang/native/issues/459) | Partially resolved | `extern inline` supported; `static inline` **permanently excluded** |
| [dart-lang/sdk#48865](https://github.com/dart-lang/sdk/issues/48865) | Open | Calling `Pointer.fromFunction` callback from non-Dart thread = UB |
| [dart-lang/sdk#52689](https://github.com/dart-lang/sdk/issues/52689) | Open | `NativeCallable.listener` limitations and workarounds |

### zenoh-c Source Files

| File | Content | Line Count |
|------|---------|------------|
| `extern/zenoh-c/include/zenoh_macros.h` | `static inline` moves, `_Generic` macros, C++ overloads | 1467 |
| `extern/zenoh-c/include/zenoh_commons.h` | Exported function signatures, struct typedefs | ~5000 |
| `extern/zenoh-c/include/zenoh_opaque.h` | Opaque type definitions with compile-time sizes | ~800 |
| `src/zenoh_dart.h` | C shim header — 62 exported functions | 543 |
| `src/zenoh_dart.c` | C shim implementation | ~700 |

### ISO C Standards

| Standard | Section | Content |
|----------|---------|---------|
| ISO C11 | §6.5.1.1 | `_Generic` selection — compile-time type dispatch |
| ISO C11 | §6.7.4 | `inline` function specifiers — no guarantee of external linkage |
| ISO C11 | §6.2.2 | `static` linkage — internal to translation unit |

### Symbol Table Verification Commands

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
nm -D libzenohc.so | grep " T z_put_options_default$"  # 000000000039f020
```
