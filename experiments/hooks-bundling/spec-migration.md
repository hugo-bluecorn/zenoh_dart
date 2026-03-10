# Migration Spec: packages/zenoh/ to @Native + Build Hooks

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CI
> **Branch**: `feature/hooks-migration`
> **Proven by**: Experiments A2 (PR #14) and consumer test (PR #17)

## Objective

Migrate `packages/zenoh/` from `DynamicLibrary.open()` to `@Native`
annotations with a build hook, eliminating `LD_LIBRARY_PATH` from all
commands. The public Dart API does not change — this is an internal
plumbing migration.

## Scope

**Changes**: ffigen config, generated bindings, native_lib.dart, 10
source files (mechanical `bindings.` prefix removal), pubspec.yaml,
new hook/build.dart, prebuilt .so placement, CLAUDE.md and README.md
command updates.

**No changes**: C shim source, public API exports, test logic, CLI
examples, CMake build system.

## Procedure

### Step 1: Add hook dependencies to pubspec.yaml

Add to `packages/zenoh/pubspec.yaml` dependencies:

```yaml
dependencies:
  args: ^2.6.0
  ffi: ^2.1.3
  hooks: ^1.0.0
  code_assets: ^1.0.0
```

### Step 2: Create hook/build.dart

Create `packages/zenoh/hook/build.dart`:

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final nativeDir = input.packageRoot.resolve('native/linux/x86_64/');

    // Primary: C shim (resolved by @Native via asset ID)
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenoh_dart.so'),
      ),
    );

    // Secondary: zenoh-c runtime (resolved by OS linker via DT_NEEDED)
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenohc.so'),
      ),
    );
  });
}
```

**Key**: CodeAsset `name` uses bare relative paths (auto-prefixed with
`package:zenoh/`). The primary asset name `src/bindings.dart` must match
the `@DefaultAsset` URI in the generated bindings.

### Step 3: Place and patch prebuilt libraries

```bash
mkdir -p packages/zenoh/native/linux/x86_64/
cp build/libzenoh_dart.so packages/zenoh/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/zenoh/native/linux/x86_64/
patchelf --set-rpath '$ORIGIN' packages/zenoh/native/linux/x86_64/libzenoh_dart.so
```

Verify:
```bash
readelf -d packages/zenoh/native/linux/x86_64/libzenoh_dart.so | grep RUNPATH
# Should show: (RUNPATH) Library runpath: [$ORIGIN]
```

### Step 4: Reconfigure ffigen for @Native output

Edit `packages/zenoh/ffigen.yaml` — add the `ffi-native` section:

```yaml
ffi-native:
  assetId: 'package:zenoh/src/bindings.dart'
```

This tells ffigen to generate `@Native` annotations with a
`@DefaultAsset('package:zenoh/src/bindings.dart')` library directive
instead of the `ZenohDartBindings` class.

### Step 5: Regenerate bindings

```bash
cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml
```

The generated `lib/src/bindings.dart` will change from:

```dart
class ZenohDartBindings {
  ZenohDartBindings(DynamicLibrary dynamicLibrary) ...
  int zd_init_dart_api_dl(Pointer<Void> data) { ... }
  ...
}
```

To:

```dart
@DefaultAsset('package:zenoh/src/bindings.dart')
library;

@Native<IntPtr Function(Pointer<Void>)>(symbol: 'zd_init_dart_api_dl')
external int zd_init_dart_api_dl(Pointer<Void> data);
...
```

All functions become top-level `external` declarations with `@Native`
annotations. No class, no constructor, no DynamicLibrary parameter.

### Step 6: Simplify native_lib.dart

Replace the current `native_lib.dart` (DynamicLibrary + lazy singleton)
with a simple initialization guard:

```dart
import 'dart:ffi';

import 'bindings.dart' as ffi_bindings;

bool _initialized = false;

/// Ensures the Dart API DL is initialized.
///
/// Must be called before any native port usage (subscribers,
/// publisher matching status). Safe to call multiple times.
void ensureInitialized() {
  if (_initialized) return;
  final result = ffi_bindings.zd_init_dart_api_dl(
    NativeApi.initializeApiDLData,
  );
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }
  _initialized = true;
}
```

No `DynamicLibrary.open()`. No lazy singleton. No platform switch. The
`@Native` runtime handles library loading.

### Step 7: Update all call sites (10 files, 84 occurrences)

Every `bindings.zd_something(...)` becomes `ffi_bindings.zd_something(...)`,
where `ffi_bindings` is the import prefix for `bindings.dart`.

**Why a prefix?** The generated function names (`zd_config_new`,
`zd_session_open`, etc.) would collide with Dart identifiers or be
confusing at call sites. Using `import 'bindings.dart' as ffi_bindings`
keeps the call sites explicit.

The mechanical transformation for each file:

1. Replace `import 'native_lib.dart';` with:
   ```dart
   import 'bindings.dart' as ffi_bindings;
   import 'native_lib.dart';
   ```
2. Replace every `bindings.zd_` with `ffi_bindings.zd_`
3. Add `ensureInitialized();` where `bindings` was previously accessed
   for the first time (the lazy init trigger). In practice, this means
   `Session.open()` and `Zenoh.initLog()` should call
   `ensureInitialized()` — they are the entry points to the library.

**Files to update:**

| File | `bindings.` count | Notes |
|------|-------------------|-------|
| `native_lib.dart` | 1 | Rewritten (Step 6) |
| `publisher.dart` | 20 | Heaviest consumer |
| `session.dart` | 17 | Entry point — add `ensureInitialized()` |
| `bytes.dart` | 12 | |
| `shm_provider.dart` | 11 | |
| `shm_mut_buffer.dart` | 7 | |
| `keyexpr.dart` | 7 | |
| `config.dart` | 4 | |
| `subscriber.dart` | 3 | |
| `zenoh.dart` | 2 | Entry point — add `ensureInitialized()` |

### Step 8: Run dart analyze

```bash
fvm dart analyze packages/zenoh
```

Must pass with no errors. The migration is mechanical — any errors
indicate a missed call site or import.

### Step 9: Run the full test suite WITHOUT LD_LIBRARY_PATH

```bash
cd packages/zenoh && fvm dart test
```

**This is the critical verification.** All 185 existing tests must pass
without `LD_LIBRARY_PATH`. The tests call the Dart API (Session,
Publisher, Subscriber, etc.), which calls through the `@Native`-resolved
FFI functions into the real `libzenoh_dart.so` and `libzenohc.so`.

If tests pass: the migration is correct.
If tests fail: the `@Native` resolution or DT_NEEDED chain has an issue.

### Step 10: Verify CLI examples WITHOUT LD_LIBRARY_PATH

```bash
cd packages/zenoh && fvm dart run example/z_info.dart
cd packages/zenoh && fvm dart run example/z_scout.dart
```

These should produce output without `LD_LIBRARY_PATH`. Use `z_info.dart`
(quick, prints ZID) and `z_scout.dart` (quick, 1-second timeout) for
verification — no need to test all 7 examples.

### Step 11: Update documentation

Remove `LD_LIBRARY_PATH` from all commands in:

1. **CLAUDE.md** — Test commands, CLI example commands, build instructions
2. **README.md** — CLI examples section, test commands
3. **packages/zenoh/README.md** (if it exists)

Replace:
```bash
cd packages/zenoh && LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build fvm dart test
```

With:
```bash
cd packages/zenoh && fvm dart test
```

**Important**: Keep the `LD_LIBRARY_PATH` in the zenoh-c build
instructions (Step "Build & Development Commands" → "zenoh-c native
library") — that's for building the library, not for using it.

Also update the "Architecture" section's note about `DynamicLibrary.open()`
and single-load library pattern — it now uses `@Native` resolution.

### Step 12: Commit and PR

Branch: `feature/hooks-migration`
PR against: `main`

Suggested commit sequence:
1. `feat(zenoh): add build hook and prebuilt native libraries`
2. `refactor(zenoh): migrate bindings from DynamicLibrary to @Native`
3. `refactor(zenoh): update all call sites to use @Native bindings`
4. `docs(zenoh): remove LD_LIBRARY_PATH from all commands`

## Acceptance Criteria

1. `fvm dart test` passes (all 185 tests) **without LD_LIBRARY_PATH**
2. `fvm dart run example/z_info.dart` works **without LD_LIBRARY_PATH**
3. `fvm dart analyze packages/zenoh` passes with no issues
4. No `DynamicLibrary.open` in `packages/zenoh/lib/src/`
5. `hook/build.dart` declares two CodeAsset entries
6. `@DefaultAsset` URI matches primary CodeAsset name
7. Prebuilt `libzenoh_dart.so` has RUNPATH `$ORIGIN`
8. `LD_LIBRARY_PATH` removed from CLAUDE.md and README.md commands
9. Public API unchanged (no export changes in `lib/zenoh.dart`)
10. All CLI examples documented without `LD_LIBRARY_PATH`

## What Can Go Wrong

### ffigen @Native output format

The `ffi-native` config may generate slightly different output than
expected (e.g., different import style, different annotation format).
CI should inspect the generated file and adjust Step 7 accordingly.

### Struct typedefs with @Native

The current ffigen config maps many zenoh-c types to `Opaque`. Verify
that `@Native` generation handles these `Opaque` type mappings the
same way as the class-based generation.

### ensureInitialized() call placement

If `ensureInitialized()` is called too late (after a `@Native` function
that uses Dart ports), the native port call will fail. The safest
approach: call it in `Session.open()` and `Zenoh.initLog()`, which are
the only two public entry points to the library.

### Existing developer workflows

Developers who build the C shim locally (via CMake) and run tests with
`LD_LIBRARY_PATH` will continue to work — `LD_LIBRARY_PATH` takes
precedence over `@Native` resolution. But the hook's prebuilt copies
in `native/linux/x86_64/` must be kept in sync with the CMake output.
Document this in the developer build instructions.

## References

- [experiments/hooks-bundling/synthesis.md](synthesis.md) — full experiment analysis
- [packages/exp_hooks_prebuilt_native/](../../packages/exp_hooks_prebuilt_native/) — A2 reference implementation
- [ffigen @Native docs](https://pub.dev/packages/ffigen#native-assets)
- [Dart @Native API](https://api.dart.dev/dart-ffi/Native-class.html)
