# Phase 0: Bootstrap (Infrastructure)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2.
It uses a C shim layer to bridge zenoh-c's macro-heavy API into a flat C API
that `dart:ffi` / `ffigen` can consume.

This is a Melos monorepo. The Dart package lives at `packages/zenoh/`.
The C shim source is at the monorepo root under `src/`.

### Architecture

```
Dart CLI example (packages/zenoh/bin/z_*.dart)
    ↓
Idiomatic Dart API (packages/zenoh/lib/src/*.dart)
    ↓
Generated FFI bindings (packages/zenoh/lib/src/bindings.dart) ← ffigen from C header
    ↓
C shim (src/zenoh_dart.h/.c) ← thin wrapper over zenoh-c
    ↓
libzenohc.so (pre-built from zenoh-c v1.7.2, SHM + unstable API enabled)
```

### Why a C shim?

zenoh-c uses `_Generic` macros (`z_loan`, `z_move`, `z_drop`, `z_closure`,
`z_recv`) that `ffigen` cannot process. The shim:

1. Flattens macros into concrete function calls
2. Bridges native callbacks to Dart via `Dart_PostCObject_DL` + `Dart_Port`
3. Simplifies lifetime management with heap-allocated handles

### Callback strategy: Dart NativePorts

- Dart: create `ReceivePort`, pass `sendPort.nativePort` (int64) to C shim
- C shim: in zenoh callback, serialize data → `Dart_PostCObject_DL`
- Dart: `ReceivePort.listen()` feeds `StreamController<T>`

### zenoh-c build (prerequisite)

zenoh-c must be built with SHM and unstable API enabled:

```bash
cmake \
  -S extern/zenoh-c \
  -B extern/zenoh-c/build \
  -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=TRUE \
  -DZENOHC_BUILD_IN_SOURCE_TREE=TRUE \
  -DZENOHC_BUILD_WITH_SHARED_MEMORY=TRUE \
  -DZENOHC_BUILD_WITH_UNSTABLE_API=TRUE

RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release
```

Build artifacts: `extern/zenoh-c/target/release/libzenohc.so`,
headers at `extern/zenoh-c/include/`.

## Current Project State

Scaffolded as a Melos monorepo with a minimal pure Dart package:

- **`src/zenoh_dart.h`**: FFI_PLUGIN_EXPORT macro only, no functions
- **`src/zenoh_dart.c`**: includes `zenoh_dart.h` only
- **`src/CMakeLists.txt`**: minimal build of `zenoh_dart.c`, no zenoh-c linking
- **`packages/zenoh/lib/zenoh.dart`**: empty barrel export
- **`packages/zenoh/lib/src/native_lib.dart`**: DynamicLibrary loader (platform-aware)
- **`packages/zenoh/lib/src/bindings.dart`**: auto-generated (empty, no C functions yet)
- **`packages/zenoh/ffigen.yaml`**: points at `../../src/zenoh_dart.h`, outputs `lib/src/bindings.dart`
- **`packages/zenoh/pubspec.yaml`**: pure Dart package, `resolution: workspace`, deps: ffi, args
- **`extern/zenoh-c/`**: submodule at v1.7.2

No `bin/` directory. No `lib/src/` subdirectory structure beyond loader/bindings.

## Prior Phases

None — this is the first phase.

## This Phase's Goal

Establish the foundation that every subsequent phase depends on:
1. Build system links `libzenohc.so` and zenoh-c headers
2. C shim provides session, config, keyexpr, bytes management
3. ffigen generates clean Dart bindings from the C shim
4. Dart library structure (`packages/zenoh/lib/src/`) with core types
5. Dart API can open and close a zenoh session

No runnable CLI example yet — just the infrastructure.

## C Shim Functions to Implement

Replace all placeholder code in `src/zenoh_dart.h` and `src/zenoh_dart.c`.

### Dart API initialization

```c
// Initialize Dart native API for NativePort messaging (call once at startup)
FFI_PLUGIN_EXPORT int zd_init_dart_api_dl(void* data);
```

Wraps `Dart_InitializeApiDL(data)`. Required before any `Dart_PostCObject_DL`
calls in subsequent phases.

### Logging

```c
// Initialize zenoh logging from ZENOH_LOG env var, or use fallback filter
FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter);
```

Wraps `zc_init_log_from_env_or(fallback_filter)`.

### Config

```c
// Create a default zenoh configuration
FFI_PLUGIN_EXPORT int zd_config_default(z_owned_config_t* config);

// Insert a JSON5 configuration value
FFI_PLUGIN_EXPORT int zd_config_insert_json5(
    const z_loaned_config_t* config, const char* key, const char* value);

// Loan a config (return pointer to loaned type)
FFI_PLUGIN_EXPORT const z_loaned_config_t* zd_config_loan(const z_owned_config_t* config);

// Drop (free) config
FFI_PLUGIN_EXPORT void zd_config_drop(z_owned_config_t* config);
```

Wraps: `z_config_default`, `zc_config_insert_json5`, `z_config_loan`, `z_config_drop`.

### Session

```c
// Open a zenoh session (consumes the config)
FFI_PLUGIN_EXPORT int zd_open_session(z_owned_session_t* session, z_owned_config_t* config);

// Get a loaned reference to the session
FFI_PLUGIN_EXPORT const z_loaned_session_t* zd_session_loan(const z_owned_session_t* session);

// Close and drop a session
FFI_PLUGIN_EXPORT void zd_close_session(z_owned_session_t* session);
```

Wraps: `z_open` (with `z_config_move`), `z_session_loan`, `z_session_drop` (with `z_session_move`).

### Key Expressions

```c
// Create a key expression view from a string (no copy, string must outlive the view)
FFI_PLUGIN_EXPORT int zd_view_keyexpr_from_str(z_view_keyexpr_t* ke, const char* expr);

// Get the key expression as a loaned reference
FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_view_keyexpr_loan(const z_view_keyexpr_t* ke);

// Convert a loaned keyexpr to a string (caller must drop the output string)
FFI_PLUGIN_EXPORT int zd_keyexpr_as_view_string(
    const z_loaned_keyexpr_t* ke, z_view_string_t* out);
```

Wraps: `z_view_keyexpr_from_str`, `z_view_keyexpr_loan`, `z_keyexpr_as_view_string`.

### Bytes (payload data)

```c
// Create bytes from a C string (copies the data)
FFI_PLUGIN_EXPORT void zd_bytes_copy_from_str(z_owned_bytes_t* bytes, const char* str);

// Create bytes from a static string (no copy — string must be static/permanent)
FFI_PLUGIN_EXPORT void zd_bytes_from_static_str(z_owned_bytes_t* bytes, const char* str);

// Create bytes from a buffer (copies len bytes from data)
FFI_PLUGIN_EXPORT void zd_bytes_copy_from_buf(
    z_owned_bytes_t* bytes, const uint8_t* data, size_t len);

// Convert bytes to a string (caller must drop the output string)
FFI_PLUGIN_EXPORT int zd_bytes_to_string(const z_loaned_bytes_t* bytes, z_owned_string_t* out);

// Get a loaned reference to bytes
FFI_PLUGIN_EXPORT const z_loaned_bytes_t* zd_bytes_loan(const z_owned_bytes_t* bytes);

// Drop (free) bytes
FFI_PLUGIN_EXPORT void zd_bytes_drop(z_owned_bytes_t* bytes);
```

Wraps: `z_bytes_copy_from_str`, `z_bytes_from_static_str`, `z_bytes_copy_from_buf`,
`z_bytes_to_string`, `z_bytes_loan`, `z_bytes_drop`.

### String utilities

```c
// Get data pointer from a loaned string
FFI_PLUGIN_EXPORT const char* zd_string_data(const z_loaned_string_t* str);

// Get length of a loaned string
FFI_PLUGIN_EXPORT size_t zd_string_len(const z_loaned_string_t* str);

// Drop (free) an owned string
FFI_PLUGIN_EXPORT void zd_string_drop(z_owned_string_t* str);

// Get data pointer from a view string
FFI_PLUGIN_EXPORT const char* zd_view_string_data(const z_view_string_t* str);

// Get length of a view string
FFI_PLUGIN_EXPORT size_t zd_view_string_len(const z_view_string_t* str);
```

Wraps: `z_string_data`, `z_string_len`, `z_string_drop`, `z_view_string_data`, `z_view_string_len`.

## Build System Changes

### `src/CMakeLists.txt`

Modify to:
- Add `target_include_directories` pointing to `${CMAKE_CURRENT_SOURCE_DIR}/../extern/zenoh-c/include`
- Find and link `libzenohc.so` from `extern/zenoh-c/target/release/`
- Add Dart native API DL support (`dart_api_dl.c` from the Dart SDK, or via ffi package)
- Keep existing platform-specific settings (Android page size, etc.)

### `packages/zenoh/ffigen.yaml`

Update to:
- Entry point: `../../src/zenoh_dart.h`
- Include directives: only `../../src/zenoh_dart.h` (not zenoh.h directly)
- Compiler opts: add `-I` for zenoh-c `include/` directory
- Output: `lib/src/bindings.dart`
- Configure opaque type handling for zenoh types

### `packages/zenoh/pubspec.yaml`

Minimal changes:
- Ensure `ffi` and `ffigen` dependencies are present (already there from scaffold)

## Dart API Surface

### New files to create

**`packages/zenoh/lib/src/native_lib.dart`** — Dynamic library loading (already exists as scaffold):
- Load `libzenoh_dart.so` (platform-aware)
- Also ensure `libzenohc.so` is loaded (either by the system linker via RPATH, or explicitly)
- Initialize Dart native API DL on first load

**`packages/zenoh/lib/src/bindings.dart`** — Auto-generated by ffigen (DO NOT EDIT)

**`packages/zenoh/lib/src/exceptions.dart`**:
- `class ZenohException implements Exception` with message and return code

**`packages/zenoh/lib/src/config.dart`**:
- `class Config` wrapping `z_owned_config_t`
  - `Config()` — creates default config
  - `Config.insertJson5(String key, String value)` — insert config value
  - `void dispose()` — drop the config

**`packages/zenoh/lib/src/session.dart`**:
- `class Session`
  - `static Session open({Config? config})` — opens session (consumes config)
  - `void close()` — closes session
  - Internal: holds pointer to `z_owned_session_t`

**`packages/zenoh/lib/src/keyexpr.dart`**:
- `class KeyExpr`
  - `KeyExpr(String expr)` — creates from string
  - `String get value` — returns the key expression string

**`packages/zenoh/lib/src/bytes.dart`**:
- `class ZBytes`
  - `ZBytes.fromString(String value)` — creates from string
  - `ZBytes.fromUint8List(Uint8List data)` — creates from byte buffer
  - `String toStr()` — converts to string
  - `void dispose()` — drop

**`packages/zenoh/lib/zenoh.dart`** — Barrel export file:
- Exports all public classes from `lib/src/`

### Files to delete/replace

- All placeholder code in `lib/zenoh.dart` (replaced with barrel exports)

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function |
|----------------|-----------------|
| `zd_init_dart_api_dl` | `Dart_InitializeApiDL` (Dart SDK) |
| `zd_init_log` | `zc_init_log_from_env_or` |
| `zd_config_default` | `z_config_default` |
| `zd_config_insert_json5` | `zc_config_insert_json5` |
| `zd_config_loan` | `z_config_loan` (macro → concrete) |
| `zd_config_drop` | `z_config_drop` (macro → concrete) |
| `zd_open_session` | `z_open` + `z_config_move` |
| `zd_session_loan` | `z_session_loan` (macro → concrete) |
| `zd_close_session` | `z_session_drop` + `z_session_move` |
| `zd_view_keyexpr_from_str` | `z_view_keyexpr_from_str` |
| `zd_view_keyexpr_loan` | `z_view_keyexpr_loan` (macro → concrete) |
| `zd_keyexpr_as_view_string` | `z_keyexpr_as_view_string` |
| `zd_bytes_copy_from_str` | `z_bytes_copy_from_str` |
| `zd_bytes_from_static_str` | `z_bytes_from_static_str` |
| `zd_bytes_copy_from_buf` | `z_bytes_copy_from_buf` |
| `zd_bytes_to_string` | `z_bytes_to_string` |
| `zd_bytes_loan` | `z_bytes_loan` (macro → concrete) |
| `zd_bytes_drop` | `z_bytes_drop` (macro → concrete) |
| `zd_string_data` | `z_string_data` |
| `zd_string_len` | `z_string_len` |
| `zd_string_drop` | `z_string_drop` (macro → concrete) |

## Reference Files

- `extern/zenoh-c/include/zenoh.h` — umbrella header
- `extern/zenoh-c/include/zenoh_commons.h` — all function signatures and types
- `extern/zenoh-c/include/zenoh_macros.h` — macro definitions (what the shim flattens)
- `extern/zenoh-c/examples/z_put.c` — simplest example using session/config/keyexpr/bytes

## Verification

1. `fvm dart run ffigen --config ffigen.yaml` generates `lib/src/bindings.dart` without errors
2. `fvm dart analyze` passes with no errors
3. Unit test: open session with default config, close it, no crash
4. Unit test: create `KeyExpr("demo/test")`, read back `value`, assert equality
5. Unit test: create `ZBytes.fromString("hello")`, convert back with `toStr()`, assert equality

## Commands Reference

All commands use `fvm` (Dart and Flutter are not on PATH):

```bash
# Regenerate FFI bindings
cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml

# Analyze
fvm dart analyze packages/zenoh

# Run tests (requires LD_LIBRARY_PATH for native libs)
cd packages/zenoh && fvm dart test

# Melos bootstrap (from monorepo root)
fvm dart run melos bootstrap
```
