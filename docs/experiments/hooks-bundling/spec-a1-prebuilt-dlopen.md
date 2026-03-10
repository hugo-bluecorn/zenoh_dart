# Experiment A1: Both-Prebuilt + DynamicLibrary.open()

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CP
> **Package**: `packages/hooks_prebuilt_dlopen/`
> **Parent**: `docs/experiments/hooks-bundling/design.md`

## Objective

Prove that two prebuilt native libraries (`libzenoh_dart.so` and
`libzenohc.so`) can be bundled via Dart build hooks and loaded at runtime
using the existing `DynamicLibrary.open()` pattern. This is the simplest
possible hooks approach — no compilation at build time, no
`native_toolchain_c` dependency.

## Independent Variables (What Makes This A1)

- **Build strategy**: Both-prebuilt (no CBuilder)
- **Loading mechanism**: `DynamicLibrary.open('libzenoh_dart.so')`

## Package Structure

```
packages/hooks_prebuilt_dlopen/
  pubspec.yaml
  hook/
    build.dart                    # declares two CodeAsset entries
  native/
    linux/
      x86_64/
        libzenoh_dart.so          # copied from build/
        libzenohc.so              # copied from extern/zenoh-c/target/release/
  lib/
    hooks_prebuilt_dlopen.dart    # public barrel export
    src/
      native_lib.dart             # DynamicLibrary.open() loader
  test/
    smoke_test.dart               # calls zd_init_dart_api_dl + zd_init_log
  lessons-learned.md              # living doc, updated during experimentation
```

## Exact File Specifications

### pubspec.yaml

```yaml
name: hooks_prebuilt_dlopen
description: "Experiment A1: both-prebuilt + DynamicLibrary.open()"
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
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:hooks_prebuilt_dlopen/src/native_lib.dart',
      linkMode: DynamicLoadingBundled(),
      file: packageRoot.resolve('native/linux/x86_64/libzenoh_dart.so'),
    ));

    // Library 2: prebuilt zenoh-c runtime (DT_NEEDED dependency)
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:hooks_prebuilt_dlopen/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: packageRoot.resolve('native/linux/x86_64/libzenohc.so'),
    ));
  });
}
```

**Note**: This hook hardcodes Linux x86_64. Platform/arch dispatch is
intentionally omitted — this experiment tests the mechanism, not
multi-platform support.

### lib/hooks_prebuilt_dlopen.dart

```dart
export 'src/native_lib.dart' show initZenohDart;
```

### lib/src/native_lib.dart

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

**Note**: This uses manual `lookupFunction` rather than ffigen-generated
bindings. Keeps the experiment minimal — we're testing the hooks mechanism,
not the bindings generator.

### test/smoke_test.dart

```dart
import 'package:hooks_prebuilt_dlopen/hooks_prebuilt_dlopen.dart';
import 'package:test/test.dart';

void main() {
  test('loads both native libraries via DynamicLibrary.open()', () {
    // This exercises:
    // 1. Hook bundled libzenoh_dart.so is found by DynamicLibrary.open()
    // 2. DT_NEEDED resolves libzenohc.so from the same bundle directory
    // 3. zd_init_dart_api_dl succeeds (proves libzenoh_dart.so loaded)
    // 4. zd_init_log succeeds (proves libzenohc.so loaded via DT_NEEDED)
    final ok = initZenohDart();
    expect(ok, isTrue);
  });
}
```

### native/ directory

Populated by copying from existing build artifacts:

```bash
mkdir -p packages/hooks_prebuilt_dlopen/native/linux/x86_64/
cp build/libzenoh_dart.so packages/hooks_prebuilt_dlopen/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/hooks_prebuilt_dlopen/native/linux/x86_64/
```

### lessons-learned.md

Initial template:

```markdown
# Experiment A1: Lessons Learned

## Approach
Both-prebuilt + DynamicLibrary.open()

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

## Recommendations for Next Experiments
```

## Acceptance Criteria

1. `hook/build.dart` declares two `CodeAsset` entries with
   `DynamicLoadingBundled()`
2. `lib/src/native_lib.dart` uses `DynamicLibrary.open('libzenoh_dart.so')`
   to load the library
3. `test/smoke_test.dart` calls `zd_init_dart_api_dl` (proves
   `libzenoh_dart.so` loaded) and `zd_init_log` (proves `libzenohc.so`
   resolved via DT_NEEDED)
4. All 6 verification criteria are tested and recorded in
   `lessons-learned.md`
5. No `LD_LIBRARY_PATH` is used in any test or run command

## What This Experiment Does NOT Test

- Multi-platform support (macOS, Windows, Android) — Linux x86_64 only
- ffigen-generated bindings — uses manual `lookupFunction`
- Full zenoh API surface — only two trivial FFI calls
- `@Native` annotations — that's experiment A2
- CBuilder compilation — that's experiments B1/B2

## Risk: DynamicLibrary.open() May Not Find Bundled Assets

Research indicates `DynamicLibrary.open('libfoo.so')` does NOT automatically
find hook-bundled assets. If this experiment fails on criterion 1 or 2, that
is a **valid negative result** — it proves that `DynamicLibrary.open()` is
incompatible with hooks bundling and `@Native` annotations (experiment A2)
are required.

Document the failure mode thoroughly in `lessons-learned.md` so A2 can
build on this knowledge.

## Commands

```bash
# Run the smoke test (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_prebuilt_dlopen && fvm dart test

# Run a minimal dart program (should work WITHOUT LD_LIBRARY_PATH)
cd packages/hooks_prebuilt_dlopen && fvm dart run example/smoke.dart
```

## References

- `docs/experiments/hooks-bundling/context.md` — full project context
- `docs/experiments/hooks-bundling/design.md` — experiment design + research
- `packages/zenoh/lib/src/native_lib.dart` — current DynamicLibrary.open() pattern
- [sqlite_prebuilt example](https://github.com/dart-lang/native/tree/main/pkgs/code_assets/example/sqlite_prebuilt)
