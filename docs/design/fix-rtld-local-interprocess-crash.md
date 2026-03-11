# Fix: @Native Inter-Process Crash

> **SUPERSEDED (2026-03-11):** This spec describes a hybrid approach (keep
> `@Native`, pre-load via `DynamicLibrary.open()`). That approach was attempted
> (commit `a9e6625`) and **failed** — `@Native`'s `NoActiveIsolateScope` taints
> the handle even after pre-load. The actual fix reverted `@Native` entirely to
> class-based `ZenohDartBindings(DynamicLibrary)`. See
> `docs/reviews/interprocess-crash-fix-review.md` for the final implementation.

**Type:** Bugfix (critical)
**Scope:** Dart initialization path (`native_lib.dart`)
**Blocks:** zenoh-counter-dart LD_LIBRARY_PATH removal, zenoh-counter-cpp interop test updates

## Background

After the hooks migration (PR #18), two separate Dart processes that connect
via zenoh TCP crash the listener process. The crash is a SIGSEGV on a tokio
worker thread (`pc=0`, `isolate_group=nil`).

Full investigation: `docs/reviews/rtld-local-crash-investigation.md`

### Root Cause

The crash is caused by `@Native`'s library loading mechanism in the Dart VM.
A definitive A/B test proved that `DynamicLibrary.open()` with the same .so
binaries works perfectly, while `@Native` crashes. No environment variable
workaround (LD_PRELOAD, LD_LIBRARY_PATH) fixes the crash under `@Native`.

Key differences in the Dart VM source (`extern/dart-sdk/runtime/`):

1. `@Native` wraps dlopen in `NoActiveIsolateScope` (detaches thread from
   isolate during loading). `DynamicLibrary.open()` does not.
2. `@Native` resolves symbols lazily on first FFI call via `FfiResolve`.
   `DynamicLibrary.open()` + `lookupFunction()` resolves eagerly.
3. `@Native` loads on a background thread. `DynamicLibrary.open()` loads on
   the main isolate thread.

### Discarded Approach: RTLD_GLOBAL Promotion

The original hypothesis was that `RTLD_LOCAL` symbol visibility caused the
crash. A C shim function `zd_promote_zenohc_global()` was implemented to
re-open `libzenohc.so` with `RTLD_GLOBAL`. This **did not fix the crash**.
LD_PRELOAD (which forces RTLD_GLOBAL) also did not fix it. The RTLD_LOCAL
hypothesis was wrong — the issue is in `@Native`'s loading mechanism itself.

## Specification

### Fix Strategy: Hybrid DynamicLibrary.open() Pre-load

Keep `@Native` annotations for FFI bindings (needed for pub.dev distribution
and build hook integration). But pre-load both native libraries eagerly via
`DynamicLibrary.open()` in `ensureInitialized()` **before** any `@Native`
call triggers lazy resolution.

When `@Native` later calls `dlopen()` on the same library path, the OS linker
returns the already-loaded handle (refcount increment). This makes the loading
behave like `DynamicLibrary.open()` while keeping `@Native` for symbol
resolution and build hook integration.

### Dart Changes

**`packages/zenoh/lib/src/native_lib.dart`:**

```dart
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:zenoh/src/bindings.dart' as ffi_bindings;

bool _initialized = false;

/// Pre-loads native libraries eagerly via DynamicLibrary.open() to work
/// around a Dart VM bug where @Native's lazy loading mechanism causes
/// crashes when two Dart processes connect via TCP.
///
/// The @Native annotations remain for symbol resolution and build hook
/// integration. When @Native later calls dlopen() on the same paths,
/// the OS linker returns the already-loaded handles.
void _preloadNativeLibraries() {
    // Discover the directory where libzenoh_dart.so is loaded from.
    // The build hook copies both .so files to .dart_tool/lib/.
    // We find the actual path by looking up a known symbol.
    final lib = DynamicLibrary.open('libzenoh_dart.so');
    // Loading libzenoh_dart.so also loads libzenohc.so via DT_NEEDED.
    // Both are now loaded eagerly on the main thread.
    // We don't close the handle — it must stay loaded.
}

void ensureInitialized() {
    if (_initialized) return;
    _preloadNativeLibraries();
    final result = ffi_bindings.zd_init_dart_api_dl(
        NativeApi.initializeApiDLData,
    );
    if (result != 0) {
        throw StateError('Failed to initialize Dart API DL (code: $result)');
    }
    _initialized = true;
}
```

**Key detail:** `DynamicLibrary.open('libzenoh_dart.so')` uses a bare library
name. The OS linker searches for it using:
1. LD_LIBRARY_PATH (if set)
2. DT_RUNPATH of the calling binary
3. /etc/ld.so.cache
4. default paths (/lib, /usr/lib)

This bare-name lookup may fail if the library isn't on any standard search
path. The build hook copies .so files to `.dart_tool/lib/` but doesn't add
that to the linker search path. Two approaches to handle this:

**Option A — Resolve the path from the build hook output:**
Read `native_assets.yaml` from `.dart_tool/` to discover the absolute path
the build hook registered, then use `DynamicLibrary.open(absolutePath)`.

**Option B — Use a C shim function to discover the path:**
Since `libzenoh_dart.so` is already partially loaded by the time `@Native`
resolves the first symbol (the call to `_preloadNativeLibraries` itself
triggers it), we can use `dladdr()` from within the C shim to find the
loaded library's filesystem path, then re-open it without
`NoActiveIsolateScope`.

**Option C — Call DynamicLibrary.open() with the absolute path:**
The path `.dart_tool/lib/libzenoh_dart.so` is predictable. Construct it
relative to the package root. This couples us to the build hook's output
location but is the simplest approach.

### C Shim Changes

**If Option B is chosen**, add a helper function:

```c
FFI_PLUGIN_EXPORT const char* zd_get_library_path(void);
```

That uses `dladdr()` to return the filesystem path of `libzenoh_dart.so`.
The Dart side uses this path for `DynamicLibrary.open(path)`.

**If Option A or C is chosen**, no C shim changes are needed. The existing
`zd_promote_zenohc_global()` from the failed approach should be **removed**.

### Build Steps

1. If C shim changes (Option B): rebuild `libzenoh_dart.so`, copy to
   `native/linux/x86_64/`, patchelf RPATH, regenerate ffigen bindings
2. If no C shim changes (Option A/C): only modify `native_lib.dart`

### Test Requirements

**Existing tests (185):** Must all pass unchanged.

**Inter-process tests** (cherry-pick from `feature/fix-rtld-local-interprocess-crash`
branch, commits `2df31a0` and `ab77d5f`):
- Helper script: `packages/zenoh/test/helpers/interprocess_connect.dart`
- Test file: `packages/zenoh/test/interprocess_test.dart`
- Currently skipped — remove skip annotations after fix lands

**Additional inter-process test for pub/sub data exchange:**
- Helper script: `packages/zenoh/test/helpers/interprocess_subscriber.dart`
- Verify payload round-trips correctly between two Dart VMs

### Verification Criteria

1. `fvm dart test` — all existing 185 tests pass
2. Inter-process connection test passes (two Dart VMs, TCP connect, no crash)
3. Inter-process pub/sub test passes (data exchange between two Dart VMs)
4. `fvm dart analyze packages/zenoh` — no issues
5. Manual smoke test: `z_sub.dart -l tcp/...` + `z_pub.dart -e tcp/...` works
6. No LD_LIBRARY_PATH or LD_PRELOAD required

### What This Fix Does NOT Change

- No changes to `@Native`/`@DefaultAsset` annotations in bindings.dart
- No changes to the build hook (`hook/build.dart`)
- No changes to existing API classes or their behavior
- No changes to ffigen.yaml

### Risk Assessment

- **Low risk:** `DynamicLibrary.open()` before `@Native` is a safe operation.
  The OS linker handles double-loading by returning the same handle.
- **No-op for in-process:** In-process tests already work. The pre-load is
  a belt-and-suspenders measure that makes inter-process work too.
- **Platform portability:** `DynamicLibrary.open()` works on all platforms
  Dart supports. No platform-specific guards needed.

### Open Questions

1. **Which path resolution option (A/B/C)?** Option C is simplest but couples
   to `.dart_tool/lib/` layout. Option B is most robust but adds a C shim
   function. Option A reads build hook metadata at runtime.
2. **Should we report this upstream?** The `@Native` loading mechanism breaks
   Rust cdylib libraries with tokio runtimes. This likely affects other
   projects. Relevant: `dart-lang/sdk#50105`.
3. **Should `zd_promote_zenohc_global()` be removed?** It doesn't fix the
   crash but is harmless. Removing it keeps the C shim clean (62 functions
   instead of 63). Recommend removal.
