# Feature Notes: Experiment A1 -- Both-Prebuilt + DynamicLibrary.open()

**Created:** 2026-03-10
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Experiment A1 tests whether two prebuilt native libraries (`libzenoh_dart.so` and `libzenohc.so`) can be bundled via Dart build hooks (`hook/build.dart` with `DynamicLoadingBundled()` CodeAssets) and loaded at runtime using `DynamicLibrary.open()` -- without `LD_LIBRARY_PATH`. This is the simplest of four controlled experiments in the hooks-bundling experiment matrix.

### Use Cases
- Eliminate `LD_LIBRARY_PATH` requirement for zenoh-dart users on Linux
- Validate Dart build hooks as a native library distribution mechanism
- Determine if `DynamicLibrary.open()` can find hook-bundled assets (hypothesis: it cannot)

### Context
This is part of a 2x2 experiment matrix (build strategy x loading mechanism). A1 is the "both-prebuilt + DynamicLibrary.open()" cell. The control package `packages/zenoh/` remains untouched throughout all experiments. The experiment package is isolated at `packages/exp_hooks_prebuilt_dlopen/`.

Prior research (in `experiments/hooks-bundling/design.md`) identified that `DynamicLibrary.open()` does NOT auto-find hook-bundled assets -- the Dart runtime uses asset ID resolution via `@Native` annotations, not the OS dynamic linker. A negative result here is expected and valuable, proving that experiment A2 (`@Native` annotations) is required.

---

## Requirements Analysis

### Functional Requirements
1. `hook/build.dart` declares two `CodeAsset` entries with `DynamicLoadingBundled()` link mode
2. `lib/src/native_lib.dart` uses `DynamicLibrary.open('libzenoh_dart.so')` to load the C shim
3. `initZenohDart()` calls `zd_init_dart_api_dl` and `zd_init_log` through manual `lookupFunction`
4. `test/smoke_test.dart` verifies FFI calls succeed without `LD_LIBRARY_PATH`
5. `example/smoke.dart` provides a runnable entry point for `fvm dart run` verification
6. `lessons-learned.md` records all 6 verification criteria results

### Non-Functional Requirements
- Code style passes `fvm dart analyze`
- No modifications to `packages/zenoh/` (control package)
- No `LD_LIBRARY_PATH` in any test or run command

### Integration Points
- Build artifacts from existing build: `build/libzenoh_dart.so` and `extern/zenoh-c/target/release/libzenohc.so`
- Root workspace glob `packages/*` automatically includes the new package
- Results inform experiment A2 (spec-a2-prebuilt-native.md)

---

## Implementation Details

### Architectural Approach
The experiment creates a minimal Dart package with a build hook that registers two prebuilt `.so` files as CodeAssets. The loading mechanism uses `DynamicLibrary.open()` (the traditional FFI approach) to test whether the Dart build hooks runtime makes these assets discoverable by the OS dynamic linker.

Data flow: `hook/build.dart` → Dart SDK build system → CodeAsset placement → `DynamicLibrary.open()` → FFI `lookupFunction` → `zd_init_dart_api_dl` + `zd_init_log`

### Design Patterns
- **Prebuilt CodeAsset**: Both libraries are pre-compiled and placed in `native/linux/x86_64/`. The hook simply declares them as `DynamicLoadingBundled()` assets with file URIs.
- **Manual FFI binding**: Only two functions are bound (`zd_init_dart_api_dl`, `zd_init_log`) via explicit `lookupFunction` calls. No ffigen.
- **Expected negative result handling**: Tests use `markTestSkipped()` instead of hard failure when `DynamicLibrary.open()` cannot find bundled assets.

### File Structure
```
packages/exp_hooks_prebuilt_dlopen/
  pubspec.yaml
  hook/build.dart
  lib/
    exp_hooks_prebuilt_dlopen.dart    # barrel export
    src/native_lib.dart               # DynamicLibrary.open + FFI
  example/smoke.dart                  # fvm dart run entry point
  native/linux/x86_64/
    libzenoh_dart.so                  # copied from build/
    libzenohc.so                      # copied from extern/zenoh-c/target/release/
  test/
    scaffold_test.dart                # Slice 1
    smoke_test.dart                   # Slice 2
  lessons-learned.md                  # Slice 3
```

### Naming Conventions
- Package name: `exp_hooks_prebuilt_dlopen` (matches experiment matrix naming from design.md)
- Asset IDs: `package:exp_hooks_prebuilt_dlopen/src/native_lib.dart` and `package:exp_hooks_prebuilt_dlopen/src/zenohc.dart`

---

## TDD Approach

### Slice Decomposition

The feature is broken into 3 slices: 2 TDD slices (red-green-refactor) and 1 documentation slice.

**Test Framework:** `package:test`
**Test Command:** `cd packages/exp_hooks_prebuilt_dlopen && fvm dart test`

### Slice Overview
| # | Slice | Automated Tests | Dependencies |
|---|-------|----------------|-------------|
| 1 | Package scaffold + build hook | 2 | None |
| 2 | DynamicLibrary.open() loads bundled library and FFI calls succeed | 5 | Slice 1 |
| 3 | Lessons-learned documentation and verification criteria | 0 (6 manual) | Slice 2 |

---

## Dependencies

### External Packages
- `ffi: ^2.1.3`: Dart FFI support (`DynamicLibrary`, `lookupFunction`, `Pointer`)
- `hooks: ^1.0.0`: Build hook framework (`hook/build.dart` entry point)
- `code_assets: ^1.0.0`: CodeAsset declarations (`DynamicLoadingBundled`, `CodeAsset`)
- `test: ^1.25.0` (dev): Test framework

### Internal Dependencies
- `build/libzenoh_dart.so`: C shim shared library (built from `src/zenoh_dart.c`)
- `extern/zenoh-c/target/release/libzenohc.so`: zenoh-c shared library (DT_NEEDED dependency)

---

## Known Limitations / Trade-offs

### Limitations
- **Linux x86_64 only**: Experiment only tests one platform. Cross-platform validation deferred to later experiments.
- **No Flutter test app**: Criterion 3 (flutter run) is N/A for this pure Dart experiment.
- **Manual FFI only**: Tests 2 functions, not the full zenoh API. Sufficient for the hooks mechanism proof.

### Trade-offs Made
- **Expected negative result accepted**: `DynamicLibrary.open()` likely cannot find hook-bundled assets. We test it anyway to empirically confirm and document the limitation.
- **Minimal scope**: Only `initZenohDart()` is tested, not session/pub/sub. The experiment validates the mechanism, not the full API.

---

## Implementation Notes

### Key Decisions
- **Manual `lookupFunction`**: Tests the hooks mechanism, not ffigen. Keeps experiment minimal.
- **Two CodeAsset entries**: Both `.so` files are separate assets. DT_NEEDED resolution depends on them being placed in the same directory by the hooks framework.
- **`markTestSkipped()` for negative results**: Tests document failure rather than hard-failing, since a negative result is a valid outcome.
- **Spec bug noted**: `native_lib.dart` needs `import 'package:ffi/ffi.dart';` for `calloc.free()` and `toNativeUtf8()`. Spec omits this.

### Future Improvements
- Experiment A2 tests `@Native` annotations which should resolve the asset discovery problem
- Experiments B1/B2 test CBuilder (compile from source) instead of prebuilt

### Potential Refactoring
- If A1 produces a negative result, A2's `native_lib.dart` will replace `DynamicLibrary.open()` with `@Native` annotations and `DefaultAsset`

---

## References

### Related Code
- `packages/zenoh/lib/src/native_lib.dart` — control package's current loading mechanism
- `experiments/hooks-bundling/spec-a1-prebuilt-dlopen.md` — experiment specification
- `experiments/hooks-bundling/design.md` — overall experiment design

### Documentation
- `experiments/hooks-bundling/README.md` — experiment matrix overview
- Dart hooks documentation: https://dart.dev/interop/c-interop#native-assets

### Issues / PRs
- None yet. Branch: `experiment/a1-prebuilt-dlopen`
