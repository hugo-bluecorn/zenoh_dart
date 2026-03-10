# Experiment B1: CBuilder + Prebuilt + DynamicLibrary.open()

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CP
> **Package**: `packages/hooks_cbuilder_dlopen/`
> **Parent**: `docs/experiments/hooks-bundling/design.md`

## Objective

Prove that `CBuilder.library()` can compile the C shim from source at
build time, linking against a prebuilt `libzenohc.so`, and that the
resulting library can be loaded via `DynamicLibrary.open()`. This mirrors
the cbl-dart pattern (production-proven) but uses the legacy Dart loading
mechanism.

## Independent Variables (What Makes This B1)

- **Build strategy**: CBuilder compiles C shim + prebuilt libzenohc.so
- **Loading mechanism**: `DynamicLibrary.open('libzenoh_dart.so')`

## Difference From A1 and A2

- A1/A2 bundle both libraries as prebuilt. B1 compiles `libzenoh_dart.so`
  from source using `CBuilder.library()` at `hook/build.dart` execution
  time.
- This requires the C source files and zenoh-c headers to be available in
  the package (vendored, since `extern/zenoh-c/` is a submodule not
  published to pub.dev).
- Adds `native_toolchain_c` dependency (EXPERIMENTAL).

## Difference From cbl-dart

cbl-dart downloads `libcblite` from a CDN. We vendor `libzenohc.so` as a
prebuilt file in the package. The CBuilder compilation step is structurally
identical: compile a shim that links against the prebuilt library.

## Package Structure

```
packages/hooks_cbuilder_dlopen/
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
  src/                            # C shim source (copied from monorepo root)
    zenoh_dart_minimal.h          # minimal header for experiment
    zenoh_dart_minimal.c          # minimal C source (two functions only)
    dart/
      dart_api_dl.c               # Dart API DL implementation
      include/
        dart_api.h
        dart_api_dl.h
        dart_native_api.h
  lib/
    hooks_cbuilder_dlopen.dart    # public barrel export
    src/
      native_lib.dart             # DynamicLibrary.open() loader
  test/
    smoke_test.dart               # calls zd_init_dart_api_dl + zd_init_log
  lessons-learned.md              # living doc, updated during experimentation
```

## Exact File Specifications

### pubspec.yaml

```yaml
name: hooks_cbuilder_dlopen
description: "Experiment B1: CBuilder + prebuilt + DynamicLibrary.open()"
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
      name: 'package:hooks_cbuilder_dlopen/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: zenohcDir.resolve('libzenohc.so'),
    ));

    // Step 2: Compile C shim from source, linking against prebuilt zenohc
    final cBuilder = CBuilder.library(
      name: 'zenoh_dart',
      assetName: 'package:hooks_cbuilder_dlopen/src/native_lib.dart',
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

**Note**: CBuilder must run AFTER the prebuilt zenohc CodeAsset is declared,
and zenohc must be in `libraryDirectories` so the linker can resolve
`-lzenohc`. CBuilder automatically adds `-Wl,-rpath,$ORIGIN` on Linux.

### src/zenoh_dart_minimal.h

A minimal header exposing only the two functions needed for the smoke test.
This avoids vendoring the full `zenoh_dart.h` which depends on many zenoh-c
types.

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

A minimal C source implementing only the two functions. This avoids
pulling in the full C shim which depends on many zenoh-c APIs.

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

**Note**: `zd_init_log` calls into `libzenohc.so` via
`zc_try_init_log_from_env()`. This validates the DT_NEEDED linkage.

### lib/hooks_cbuilder_dlopen.dart

```dart
export 'src/native_lib.dart' show initZenohDart;
```

### lib/src/native_lib.dart

Identical pattern to A1 — `DynamicLibrary.open()` with manual
`lookupFunction`:

```dart
import 'dart:ffi';
import 'dart:io';

typedef ZdInitDartApiDlNative = IntPtr Function(Pointer<Void>);
typedef ZdInitDartApiDl = int Function(Pointer<Void>);

typedef ZdInitLogNative = Void Function(Pointer<Utf8>);
typedef ZdInitLog = void Function(Pointer<Utf8>);

DynamicLibrary? _lib;

DynamicLibrary _openLibrary() {
  if (_lib != null) return _lib!;
  if (Platform.isLinux || Platform.isAndroid) {
    _lib = DynamicLibrary.open('libzenoh_dart.so');
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
  return _lib!;
}

/// Initialize Dart API DL and zenoh logger. Returns true on success.
bool initZenohDart() {
  final lib = _openLibrary();

  final initApi = lib.lookupFunction<ZdInitDartApiDlNative, ZdInitDartApiDl>(
    'zd_init_dart_api_dl',
  );
  final result = initApi(NativeApi.initializeApiDLData);
  if (result != 0) return false;

  final initLog = lib.lookupFunction<ZdInitLogNative, ZdInitLog>(
    'zd_init_log',
  );
  final filter = 'error'.toNativeUtf8();
  initLog(filter);
  calloc.free(filter);

  return true;
}
```

### test/smoke_test.dart

```dart
import 'package:hooks_cbuilder_dlopen/hooks_cbuilder_dlopen.dart';
import 'package:test/test.dart';

void main() {
  test('loads CBuilder-compiled shim via DynamicLibrary.open()', () {
    // This exercises:
    // 1. CBuilder successfully compiled libzenoh_dart.so from source
    // 2. Hook bundled libzenoh_dart.so is found by DynamicLibrary.open()
    // 3. DT_NEEDED resolves libzenohc.so from the same bundle directory
    // 4. zd_init_dart_api_dl succeeds (proves libzenoh_dart.so loaded)
    // 5. zd_init_log succeeds (proves libzenohc.so loaded via DT_NEEDED)
    final ok = initZenohDart();
    expect(ok, isTrue);
  });
}
```

### native/ directory

Only libzenohc.so (C shim is compiled by CBuilder):

```bash
mkdir -p packages/hooks_cbuilder_dlopen/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/hooks_cbuilder_dlopen/native/linux/x86_64/
```

### include/ directory

Vendored zenoh-c headers (subset needed for compilation):

```bash
mkdir -p packages/hooks_cbuilder_dlopen/include/
cp extern/zenoh-c/include/zenoh.h packages/hooks_cbuilder_dlopen/include/
cp extern/zenoh-c/include/zenoh_commons.h packages/hooks_cbuilder_dlopen/include/
cp extern/zenoh-c/include/zenoh_macros.h packages/hooks_cbuilder_dlopen/include/
```

### src/dart/ directory

Vendored Dart API DL files (needed for `Dart_InitializeApiDL`):

```bash
mkdir -p packages/hooks_cbuilder_dlopen/src/dart/include/
cp src/dart/dart_api_dl.c packages/hooks_cbuilder_dlopen/src/dart/
cp src/dart/include/dart_api.h packages/hooks_cbuilder_dlopen/src/dart/include/
cp src/dart/include/dart_api_dl.h packages/hooks_cbuilder_dlopen/src/dart/include/
cp src/dart/include/dart_native_api.h packages/hooks_cbuilder_dlopen/src/dart/include/
```

### lessons-learned.md

Initial template:

```markdown
# Experiment B1: Lessons Learned

## Approach
CBuilder + prebuilt + DynamicLibrary.open()

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

## Unexpected Findings

## Comparison with A1 and A2

## Recommendations for Next Experiments
```

## Acceptance Criteria

1. `hook/build.dart` uses `CBuilder.library()` to compile the C shim from
   source, linking against prebuilt `libzenohc.so` via `libraries` and
   `libraryDirectories` parameters
2. `hook/build.dart` also declares prebuilt `libzenohc.so` as a `CodeAsset`
   with `DynamicLoadingBundled()`
3. C source, zenoh-c headers, and Dart API DL files are vendored in the
   package (not referencing `extern/` or monorepo root `src/`)
4. `lib/src/native_lib.dart` uses `DynamicLibrary.open('libzenoh_dart.so')`
5. `test/smoke_test.dart` calls both `zd_init_dart_api_dl` and
   `zd_init_log`
6. All 6 verification criteria tested and recorded in `lessons-learned.md`
7. No `LD_LIBRARY_PATH` is used in any test or run command

## What This Experiment Does NOT Test

- Multi-platform support — Linux x86_64 only
- Full C shim compilation (62 functions) — minimal 2-function subset
- ffigen-generated bindings — uses manual `lookupFunction`
- `@Native` annotations — that's experiment B2
- Both-prebuilt strategy — that's experiments A1/A2

## Risks

### CBuilder may fail to compile

`native_toolchain_c` is EXPERIMENTAL and may have unexpected behavior
with our compilation flags (`-DZ_FEATURE_SHARED_MEMORY`,
`-DZ_FEATURE_UNSTABLE_API`) or header paths. Document any compilation
errors thoroughly in `lessons-learned.md`.

### Header vendoring complexity

The minimal C source needs `zenoh.h` which transitively includes
`zenoh_commons.h` and `zenoh_macros.h`. If these headers have further
transitive includes, more files may need vendoring. The experiment will
reveal the true header dependency tree.

### DynamicLibrary.open() may not find CBuilder output

Same risk as A1 — `DynamicLibrary.open()` may not find hook-bundled
assets. If this fails but B2 (with `@Native`) succeeds, it confirms the
loading mechanism is the issue, not the build strategy.

## Commands

```bash
# Run the smoke test (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_cbuilder_dlopen && fvm dart test

# Run a minimal dart program (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_cbuilder_dlopen && fvm dart run example/smoke.dart
```

## References

- `docs/experiments/hooks-bundling/context.md` — full project context
- `docs/experiments/hooks-bundling/design.md` — experiment design + research
- `docs/experiments/hooks-bundling/spec-a1-prebuilt-dlopen.md` — A1 (same loading mechanism)
- [cbl-dart hook/build.dart](https://github.com/cbl-dart/cbl-dart/tree/main/packages/cbl) — production two-library reference
- [native_dynamic_linking example](https://github.com/dart-lang/native/tree/main/pkgs/hooks/example/build/native_dynamic_linking) — CBuilder with dependencies
- [CBuilder API](https://pub.dev/documentation/native_toolchain_c/latest/native_toolchain_c/CBuilder-class.html)
