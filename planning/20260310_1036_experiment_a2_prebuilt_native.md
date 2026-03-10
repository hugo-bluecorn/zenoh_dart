# Feature Notes: Experiment A2 -- Prebuilt + @Native Annotations

**Created:** 2026-03-10
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Experiment A2 tests whether two prebuilt native libraries (`libzenoh_dart.so` and `libzenohc.so`) can be bundled via Dart build hooks and loaded at runtime using `@Native` annotations with `@DefaultAsset` asset ID resolution -- eliminating `LD_LIBRARY_PATH` entirely. This follows A1's negative result which proved `DynamicLibrary.open()` is incompatible with hook-bundled assets.

### Use Cases
- Eliminate `LD_LIBRARY_PATH` requirement for zenoh-dart users on Linux
- Validate `@Native` as the correct loading mechanism for hook-bundled assets
- Test DT_NEEDED dependency resolution with RUNPATH patching (discovered from A1)

### Context
This is part of a 2x2 experiment matrix (build strategy x loading mechanism). A2 is the "both-prebuilt + @Native annotations" cell. A1 (same build strategy, `DynamicLibrary.open()`) failed because the OS dynamic linker cannot read hook-registered CodeAsset metadata -- only the Dart runtime's `@Native` resolution can. A2 tests whether `@Native` resolves this gap.

A1 also revealed that prebuilt `libzenoh_dart.so` has an absolute RUNPATH from the build machine. A2 must patch this to `$ORIGIN` using `patchelf` so the DT_NEEDED dependency (`libzenohc.so`) resolves when both files are co-located.

---

## Requirements Analysis

### Functional Requirements
1. `hook/build.dart` declares two `CodeAsset` entries with `DynamicLoadingBundled()` link mode
2. `lib/src/bindings.dart` uses `@DefaultAsset` library directive + `@Native` external functions
3. No `DynamicLibrary.open()` anywhere in the package
4. `initZenohDart()` calls `zd_init_dart_api_dl` and `zd_init_log` through @Native-resolved functions
5. `example/smoke.dart` runs without `LD_LIBRARY_PATH`
6. Prebuilt `libzenoh_dart.so` has RUNPATH patched to `$ORIGIN`
7. `lessons-learned.md` records all 6 verification criteria with A1 comparison

### Non-Functional Requirements
- Code style passes `fvm dart analyze`
- No modifications to `packages/zenoh/` (control package)
- No `LD_LIBRARY_PATH` in any command

### Integration Points
- Build artifacts: `build/libzenoh_dart.so` and `extern/zenoh-c/target/release/libzenohc.so`
- Root workspace glob `packages/*` includes the package
- Results inform experiments B1 and B2

---

## Implementation Details

### Architectural Approach
The experiment uses `@Native` annotations (Dart 3.x FFI feature) for symbol resolution. The `@DefaultAsset` library-level directive tells the Dart runtime which CodeAsset provides the symbols. The build hook registers both `.so` files as CodeAssets; the primary one matches the `@DefaultAsset` URI, the secondary one is bundled for DT_NEEDED resolution.

Data flow: `hook/build.dart` → Dart SDK build system → CodeAsset placement → `@Native` resolution via asset ID → `zd_init_dart_api_dl` + `zd_init_log` → DT_NEEDED resolves `libzenohc.so` via `$ORIGIN` RUNPATH

### Design Patterns
- **@Native + @DefaultAsset**: Dart runtime resolves symbols from the CodeAsset matching the asset URI, bypassing `ld.so` entirely for the primary library.
- **DT_NEEDED + RUNPATH**: The secondary library (`libzenohc.so`) is still resolved by the OS linker via the DT_NEEDED entry in `libzenoh_dart.so`. RUNPATH must be `$ORIGIN` for this to work.
- **Graceful degradation**: Tests use `markTestSkipped()` on failure (same pattern as A1).

### File Structure
```
packages/exp_hooks_prebuilt_native/
  pubspec.yaml
  hook/build.dart
  native/linux/x86_64/
    libzenoh_dart.so          # RUNPATH patched to $ORIGIN
    libzenohc.so
  lib/
    exp_hooks_prebuilt_native.dart
    src/bindings.dart         # @DefaultAsset + @Native
  test/
    scaffold_test.dart
    smoke_test.dart
  example/smoke.dart
  lessons-learned.md
```

### Naming Conventions
- Package: `exp_hooks_prebuilt_native` (matrix naming from design.md)
- Asset ID: `package:exp_hooks_prebuilt_native/src/bindings.dart`
- Branch: `experiment/a2-prebuilt-native`

---

## TDD Approach

### Slice Decomposition

3 slices: all with automated tests plus post-implementation documentation.

**Test Framework:** `package:test`
**Test Command:** `cd packages/exp_hooks_prebuilt_native && fvm dart test`

### Slice Overview
| # | Slice | Automated Tests | Dependencies |
|---|-------|----------------|-------------|
| 1 | Package scaffold + build hook + @Native bindings | 3 | None |
| 2 | @Native asset resolution smoke tests | 4 | Slice 1 |
| 3 | dart run verification + lessons-learned | 2 | Slice 2 |

---

## Dependencies

### External Packages
- `ffi: ^2.1.3`: Dart FFI types and `@Native` support
- `hooks: ^1.0.0`: Build hook framework
- `code_assets: ^1.0.0`: CodeAsset declarations
- `test: ^1.25.0` (dev): Test framework

### Internal Dependencies
- `build/libzenoh_dart.so`: C shim shared library
- `extern/zenoh-c/target/release/libzenohc.so`: zenoh-c shared library

### System Dependencies
- `patchelf`: For RUNPATH patching of prebuilt `libzenoh_dart.so`

---

## Known Limitations / Trade-offs

### Limitations
- Linux x86_64 only: Cross-platform validation deferred
- No Flutter test app: Criterion 3 is N/A
- Only tests 2 FFI functions: Sufficient for mechanism proof

### Trade-offs Made
- **RUNPATH patching**: Adds a manual step but is necessary for DT_NEEDED resolution. A production solution would use CBuilder (experiments B1/B2) to set RUNPATH at compile time.
- **@Native over DynamicLibrary.open()**: A1 proved open() doesn't work with hooks. @Native is the only viable path for hook-bundled assets.

---

## Implementation Notes

### Key Decisions
- **@DefaultAsset URI matches hook asset name**: This is how the Dart runtime connects @Native functions to the correct CodeAsset.
- **patchelf for RUNPATH**: The prebuilt library has an absolute RUNPATH from CMake. `patchelf --set-rpath '$ORIGIN'` makes it relocatable.
- **Two CodeAssets, one @DefaultAsset**: Only the primary library uses @Native resolution. The secondary library piggybacks via DT_NEEDED.

### Future Improvements
- Experiments B1/B2 will test CBuilder (compile from source) which sets RUNPATH correctly at build time
- If A2 succeeds, `packages/zenoh/` migration can use the @Native + prebuilt pattern

### Potential Refactoring
- If both A2 and B experiments succeed, the shared hook/loading patterns could be extracted into a utility

---

## References

### Related Code
- `packages/exp_hooks_prebuilt_dlopen/` — A1 experiment (structural reference)
- `packages/exp_hooks_prebuilt_dlopen/lessons-learned.md` — A1 results
- `packages/zenoh/lib/src/native_lib.dart` — control package loading mechanism
- `experiments/hooks-bundling/spec-a2-prebuilt-native.md` — experiment specification

### Documentation
- `experiments/hooks-bundling/design.md` — overall experiment design
- `experiments/hooks-bundling/README.md` — experiment matrix overview

### Issues / PRs
- PR #13: Experiment A1 (merged)
