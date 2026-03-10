# Experiment B2: CBuilder + Prebuilt + @Native Annotations

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CP
> **Package**: `packages/exp_hooks_cbuilder_native/`
> **Parent**: `experiments/hooks-bundling/design.md`

## Objective

Prove that `CBuilder.library()` can compile the C shim from source at
build time, linking against a prebuilt `libzenohc.so`, and that the
resulting library can be loaded via `@Native` annotations with automatic
asset ID resolution. This combines the cbl-dart build pattern with the
officially recommended loading mechanism.

## Independent Variables (What Makes This B2)

- **Build strategy**: CBuilder compiles C shim + prebuilt libzenohc.so
- **Loading mechanism**: `@Native` annotations with `@DefaultAsset`

## Relationship to Other Experiments

- **vs A2**: Same loading mechanism (`@Native`), different build strategy
  (CBuilder vs prebuilt). Isolates whether CBuilder introduces issues.
- **vs B1**: Same build strategy (CBuilder), different loading mechanism
  (`@Native` vs `DynamicLibrary.open()`). Isolates the loading variable.
- **vs cbl-dart**: cbl-dart uses CBuilder + `DynamicLibrary.open()` (our
  B1 pattern). B2 tests whether `@Native` works with CBuilder output.

## Package Structure

```
packages/exp_hooks_cbuilder_native/
  pubspec.yaml
  hook/
    build.dart                    # CBuilder + CodeAsset for prebuilt
  native/
    linux/
      x86_64/
        libzenohc.so              # prebuilt only (C shim compiled by CBuilder)
  include/                        # vendored zenoh-c headers (subset)
    zenoh.h
    zenoh_commons.h
    zenoh_macros.h
  src/                            # C shim source (minimal, self-contained)
    zenoh_dart_minimal.h
    zenoh_dart_minimal.c
    dart/
      dart_api_dl.c
      include/
        dart_api.h
        dart_api_dl.h
        dart_native_api.h
  lib/
    exp_hooks_cbuilder_native.dart    # public barrel export
    src/
      bindings.dart               # @Native annotated FFI declarations
  test/
    smoke_test.dart               # calls zd_init_dart_api_dl + zd_init_log
  lessons-learned.md              # living doc, updated during experimentation
```

## Exact File Specifications

### pubspec.yaml

```yaml
name: exp_hooks_cbuilder_native
description: "Experiment B2: CBuilder + prebuilt + @Native annotations"
version: 0.0.1
publish_to: none

resolution: workspace

environment:
  sdk: ^3.11.0

dependencies:
  ffi: ^2.1.3
  hooks: ^1.0.0
  code_assets: ^1.0.0
  native_toolchain_c: ^0.17.5    # EXPERIMENTAL

dev_dependencies:
  test: ^1.25.0
```

### hook/build.dart

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageRoot = input.packageRoot;
    final zenohcDir = packageRoot.resolve('native/linux/x86_64/');

    // Step 1: Bundle prebuilt libzenohc.so
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:exp_hooks_cbuilder_native/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: zenohcDir.resolve('libzenohc.so'),
    ));

    // Step 2: Compile C shim from source, linking against prebuilt zenohc
    // CBuilder auto-adds the CodeAsset with the assetName
    final cBuilder = CBuilder.library(
      name: 'zenoh_dart',
      assetName: 'package:exp_hooks_cbuilder_native/src/bindings.dart',
      sources: [
        'src/zenoh_dart_minimal.c',
        'src/dart/dart_api_dl.c',
      ],
      includes: [
        'include/',
        'src/dart/include/',
      ],
      defines: {
        'DART_SHARED_LIB': null,
        'Z_FEATURE_SHARED_MEMORY': null,
        'Z_FEATURE_UNSTABLE_API': null,
      },
      libraries: ['zenohc'],
      libraryDirectories: [zenohcDir.toFilePath()],
    );
    await cBuilder.run(input: input, output: output);
  });
}
```

**Critical**: CBuilder's `assetName` must match the `@DefaultAsset` URI
in `bindings.dart`. CBuilder automatically creates the CodeAsset with
`DynamicLoadingBundled()` using this asset name.

### src/zenoh_dart_minimal.h

Identical to B1:

```c
#ifndef ZENOH_DART_MINIMAL_H
#define ZENOH_DART_MINIMAL_H

#include <stdint.h>

#if defined(_WIN32) || defined(__CYGWIN__)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

FFI_PLUGIN_EXPORT intptr_t zd_init_dart_api_dl(void* data);
FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter);

#endif
```

### src/zenoh_dart_minimal.c

Identical to B1:

```c
#include "zenoh_dart_minimal.h"
#include <zenoh.h>
#include "dart/include/dart_api_dl.h"

FFI_PLUGIN_EXPORT intptr_t zd_init_dart_api_dl(void* data) {
    return Dart_InitializeApiDL(data);
}

FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter) {
    zc_try_init_log_from_env();
}
```

### lib/exp_hooks_cbuilder_native.dart

```dart
export 'src/bindings.dart' show initZenohDart;
```

### lib/src/bindings.dart

Identical pattern to A2 — `@Native` with `@DefaultAsset`:

```dart
@DefaultAsset('package:exp_hooks_cbuilder_native/src/bindings.dart')
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

### test/smoke_test.dart

```dart
import 'package:exp_hooks_cbuilder_native/exp_hooks_cbuilder_native.dart';
import 'package:test/test.dart';

void main() {
  test('loads CBuilder-compiled shim via @Native annotation', () {
    // This exercises:
    // 1. CBuilder successfully compiled libzenoh_dart.so from source
    // 2. @Native resolves zd_init_dart_api_dl via asset ID mapping
    // 3. DT_NEEDED resolves libzenohc.so from the same bundle directory
    // 4. zd_init_dart_api_dl succeeds (proves libzenoh_dart.so loaded)
    // 5. zd_init_log succeeds (proves libzenohc.so loaded via DT_NEEDED)
    final ok = initZenohDart();
    expect(ok, isTrue);
  });
}
```

### native/ directory

Only libzenohc.so (C shim compiled by CBuilder):

```bash
mkdir -p packages/exp_hooks_cbuilder_native/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/exp_hooks_cbuilder_native/native/linux/x86_64/
```

### include/ directory

Vendored zenoh-c headers (same as B1):

```bash
mkdir -p packages/exp_hooks_cbuilder_native/include/
cp extern/zenoh-c/include/zenoh.h packages/exp_hooks_cbuilder_native/include/
cp extern/zenoh-c/include/zenoh_commons.h packages/exp_hooks_cbuilder_native/include/
cp extern/zenoh-c/include/zenoh_macros.h packages/exp_hooks_cbuilder_native/include/
```

### src/dart/ directory

Vendored Dart API DL files (same as B1):

```bash
mkdir -p packages/exp_hooks_cbuilder_native/src/dart/include/
cp src/dart/dart_api_dl.c packages/exp_hooks_cbuilder_native/src/dart/
cp src/dart/include/dart_api.h packages/exp_hooks_cbuilder_native/src/dart/include/
cp src/dart/include/dart_api_dl.h packages/exp_hooks_cbuilder_native/src/dart/include/
cp src/dart/include/dart_native_api.h packages/exp_hooks_cbuilder_native/src/dart/include/
```

### lessons-learned.md

Initial template:

```markdown
# Experiment B2: Lessons Learned

## Approach
CBuilder + prebuilt + @Native annotations

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

## CBuilder-Specific Observations
- Compilation time:
- Header vendoring friction:
- native_toolchain_c stability:
- CBuilder assetName + @DefaultAsset alignment:

## Unexpected Findings

## Comparison with A1, A2, and B1

## Final Recommendation
(This is the last experiment — include a cross-experiment comparison)
```

## Acceptance Criteria

1. `hook/build.dart` uses `CBuilder.library()` with `assetName` matching
   the `@DefaultAsset` URI in `bindings.dart`
2. `hook/build.dart` also declares prebuilt `libzenohc.so` as a `CodeAsset`
3. C source, zenoh-c headers, and Dart API DL files are vendored in the
   package
4. `lib/src/bindings.dart` uses `@Native` annotations with
   `@DefaultAsset` — no `DynamicLibrary.open()` anywhere
5. `test/smoke_test.dart` calls both `zd_init_dart_api_dl` and
   `zd_init_log`
6. All 6 verification criteria tested and recorded in `lessons-learned.md`
7. No `LD_LIBRARY_PATH` is used in any test or run command
8. `lessons-learned.md` includes cross-experiment comparison (final spec)

## What This Experiment Does NOT Test

- Multi-platform support — Linux x86_64 only
- Full C shim compilation (62 functions) — minimal 2-function subset
- ffigen-generated bindings — uses hand-written `@Native` declarations
- `DynamicLibrary.open()` — that's B1
- Both-prebuilt strategy — that's A1/A2

## Risks

### CBuilder + @Native asset ID alignment

CBuilder internally creates a `CodeAsset` with the `assetName` as its
asset ID. This must exactly match the `@DefaultAsset` URI. If CBuilder
adds a package prefix or transforms the name, the resolution will fail.
The `native_dynamic_linking` example uses `assetName: 'add.dart'` which
works, but our fully-qualified URI format
(`package:exp_hooks_cbuilder_native/src/bindings.dart`) may behave differently.

### Same risks as B1

- CBuilder compilation flags/header paths
- Header vendoring dependency tree
- `native_toolchain_c` EXPERIMENTAL stability

## Commands

```bash
# Run the smoke test (should work WITHOUT LD_LIBRARY_PATH)
cd packages/exp_hooks_cbuilder_native && fvm dart test

# Run a minimal dart program (should work WITHOUT LD_LIBRARY_PATH)
cd packages/exp_hooks_cbuilder_native && fvm dart run example/smoke.dart
```

## References

- `experiments/hooks-bundling/context.md` — full project context
- `experiments/hooks-bundling/design.md` — experiment design + research
- `experiments/hooks-bundling/spec-a2-prebuilt-native.md` — A2 (same loading mechanism)
- `experiments/hooks-bundling/spec-b1-cbuilder-dlopen.md` — B1 (same build strategy)
- [cbl-dart hook/build.dart](https://github.com/cbl-dart/cbl-dart/tree/main/packages/cbl) — production reference
- [native_dynamic_linking example](https://github.com/dart-lang/native/tree/main/pkgs/hooks/example/build/native_dynamic_linking) — CBuilder with dependencies
- [CBuilder API](https://pub.dev/documentation/native_toolchain_c/latest/native_toolchain_c/CBuilder-class.html)
- [@Native API docs](https://api.dart.dev/dart-ffi/Native-class.html)
