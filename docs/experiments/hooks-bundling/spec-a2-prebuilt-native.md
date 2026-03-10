# Experiment A2: Both-Prebuilt + @Native Annotations

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CP
> **Package**: `packages/hooks_prebuilt_native/`
> **Parent**: `docs/experiments/hooks-bundling/design.md`

## Objective

Prove that two prebuilt native libraries (`libzenoh_dart.so` and
`libzenohc.so`) can be bundled via Dart build hooks and loaded at runtime
using `@Native` annotations with automatic asset ID resolution. This
eliminates `DynamicLibrary.open()` entirely — symbol resolution happens
through the hooks framework's asset mapping.

## Independent Variables (What Makes This A2)

- **Build strategy**: Both-prebuilt (no CBuilder)
- **Loading mechanism**: `@Native` annotations with `@DefaultAsset`

## Difference From A1

A1 uses `DynamicLibrary.open('libzenoh_dart.so')` — the OS dynamic linker
must find the library on its search path. Research indicates this may not
work with hook-bundled assets.

A2 uses `@Native` annotations — the Dart runtime resolves symbols via the
asset ID declared in `hook/build.dart`'s `CodeAsset(name: ...)`. The asset
ID `package:hooks_prebuilt_native/src/bindings.dart` maps directly to the
bundled library. No OS search path needed.

## Package Structure

```
packages/hooks_prebuilt_native/
  pubspec.yaml
  hook/
    build.dart                    # declares two CodeAsset entries
  native/
    linux/
      x86_64/
        libzenoh_dart.so          # copied from build/
        libzenohc.so              # copied from extern/zenoh-c/target/release/
  lib/
    hooks_prebuilt_native.dart    # public barrel export
    src/
      bindings.dart               # @Native annotated FFI declarations
  test/
    smoke_test.dart               # calls zd_init_dart_api_dl + zd_init_log
  lessons-learned.md              # living doc, updated during experimentation
```

## Exact File Specifications

### pubspec.yaml

```yaml
name: hooks_prebuilt_native
description: "Experiment A2: both-prebuilt + @Native annotations"
version: 0.0.1
publish_to: none

resolution: workspace

environment:
  sdk: ^3.11.0

dependencies:
  ffi: ^2.1.3
  hooks: ^1.0.0
  code_assets: ^1.0.0

dev_dependencies:
  test: ^1.25.0
```

### hook/build.dart

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageRoot = input.packageRoot;

    // Library 1: prebuilt C shim
    // name MUST match the @DefaultAsset library URI in bindings.dart
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:hooks_prebuilt_native/src/bindings.dart',
      linkMode: DynamicLoadingBundled(),
      file: packageRoot.resolve('native/linux/x86_64/libzenoh_dart.so'),
    ));

    // Library 2: prebuilt zenoh-c runtime (DT_NEEDED dependency)
    // name does NOT need to match any Dart file — this lib is resolved
    // by the OS dynamic linker, not by @Native asset resolution
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:hooks_prebuilt_native/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: packageRoot.resolve('native/linux/x86_64/libzenohc.so'),
    ));
  });
}
```

**Critical**: The `name` for libzenoh_dart.so must exactly match the
`@DefaultAsset` URI in `bindings.dart`. The `name` for libzenohc.so is
arbitrary — it only needs to be bundled so the OS linker can resolve it
via DT_NEEDED when libzenoh_dart.so is loaded.

### lib/hooks_prebuilt_native.dart

```dart
export 'src/bindings.dart' show initZenohDart;
```

### lib/src/bindings.dart

```dart
@DefaultAsset('package:hooks_prebuilt_native/src/bindings.dart')
library;

import 'dart:ffi';

/// Initializes the Dart native API for dynamic linking.
/// Returns 0 on success.
@Native<IntPtr Function(Pointer<Void>)>(symbol: 'zd_init_dart_api_dl')
external int zdInitDartApiDl(Pointer<Void> data);

/// Initializes the zenoh logger with a fallback filter string.
/// This calls into libzenohc.so (proves DT_NEEDED resolution).
@Native<Void Function(Pointer<Utf8>)>(symbol: 'zd_init_log')
external void zdInitLog(Pointer<Utf8> fallbackFilter);

/// Convenience wrapper for smoke testing.
bool initZenohDart() {
  final result = zdInitDartApiDl(NativeApi.initializeApiDLData);
  if (result != 0) return false;

  final filter = 'error'.toNativeUtf8();
  zdInitLog(filter);
  calloc.free(filter);

  return true;
}
```

**Key differences from A1**:
- No `DynamicLibrary.open()` — symbols resolve via `@Native` + asset ID
- `@DefaultAsset` on the library declaration sets the default asset ID
  for all `@Native` functions in this file
- The `symbol:` parameter maps Dart function names to C symbol names

### test/smoke_test.dart

```dart
import 'package:hooks_prebuilt_native/hooks_prebuilt_native.dart';
import 'package:test/test.dart';

void main() {
  test('loads both native libraries via @Native annotation', () {
    // This exercises:
    // 1. @Native resolves zd_init_dart_api_dl via asset ID mapping
    // 2. DT_NEEDED resolves libzenohc.so from the same bundle directory
    // 3. zd_init_dart_api_dl succeeds (proves libzenoh_dart.so loaded)
    // 4. zd_init_log succeeds (proves libzenohc.so loaded via DT_NEEDED)
    final ok = initZenohDart();
    expect(ok, isTrue);
  });
}
```

### native/ directory

Same as A1 — populated by copying from existing build artifacts:

```bash
mkdir -p packages/hooks_prebuilt_native/native/linux/x86_64/
cp build/libzenoh_dart.so packages/hooks_prebuilt_native/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/hooks_prebuilt_native/native/linux/x86_64/
```

### lessons-learned.md

Initial template:

```markdown
# Experiment A2: Lessons Learned

## Approach
Both-prebuilt + @Native annotations

## Results

### Criterion 1: `fvm dart run` finds bundled libs
- [ ] Pass / Fail
- Notes:

### Criterion 2: `fvm dart test` finds bundled libs
- [ ] Pass / Fail
- Notes:

### Criterion 3: `fvm flutter run` finds bundled libs
- [ ] Pass / Fail
- Notes:

### Criterion 4: DT_NEEDED dependency resolves
- [ ] Pass / Fail
- Notes:

### Criterion 5: Hook build succeeds on Linux x86_64
- [ ] Pass / Fail
- Notes:

### Criterion 6: Error reporting quality
- [ ] Adequate / Inadequate
- Notes:

## Unexpected Findings

## Comparison with A1

## Recommendations for Next Experiments
```

## Acceptance Criteria

1. `hook/build.dart` declares two `CodeAsset` entries with
   `DynamicLoadingBundled()`, where the primary asset's `name` matches the
   `@DefaultAsset` URI in `bindings.dart`
2. `lib/src/bindings.dart` uses `@Native` annotations with
   `@DefaultAsset` — no `DynamicLibrary.open()` anywhere in the package
3. `test/smoke_test.dart` calls `zd_init_dart_api_dl` (proves
   `libzenoh_dart.so` loaded via asset resolution) and `zd_init_log`
   (proves `libzenohc.so` resolved via DT_NEEDED)
4. All 6 verification criteria are tested and recorded in
   `lessons-learned.md`
5. No `LD_LIBRARY_PATH` is used in any test or run command
6. `lessons-learned.md` includes a comparison section with A1 results

## What This Experiment Does NOT Test

- Multi-platform support (macOS, Windows, Android) — Linux x86_64 only
- ffigen-generated bindings — uses hand-written `@Native` declarations
- Full zenoh API surface — only two trivial FFI calls
- `DynamicLibrary.open()` — that's experiment A1
- CBuilder compilation — that's experiments B1/B2

## Expected Outcome

Based on research, this approach has the highest probability of success.
The `@Native` + `@DefaultAsset` pattern is the officially recommended way
to resolve hook-bundled native libraries. The Dart runtime maps the asset
ID directly to the bundled library path without relying on the OS dynamic
linker search path.

If A1 fails but A2 succeeds, it confirms that `@Native` annotations are
required for hooks bundling and the existing `packages/zenoh/` code will
need to migrate away from `DynamicLibrary.open()`.

## Commands

```bash
# Run the smoke test (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_prebuilt_native && fvm dart test

# Run a minimal dart program (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_prebuilt_native && fvm dart run example/smoke.dart
```

## References

- `docs/experiments/hooks-bundling/context.md` — full project context
- `docs/experiments/hooks-bundling/design.md` — experiment design + research
- `docs/experiments/hooks-bundling/spec-a1-prebuilt-dlopen.md` — companion A1 spec
- [Flutter FFI guide: @Native resolution](https://docs.flutter.dev/platform-integration/bind-native-code)
- [@Native API docs](https://api.dart.dev/dart-ffi/Native-class.html)
- [sqlite_prebuilt example](https://github.com/dart-lang/native/tree/main/pkgs/code_assets/example/sqlite_prebuilt)
