# Feature Notes: Experiment B1 -- CBuilder + DynamicLibrary.open()

**Created:** 2026-03-10
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Experiment B1 tests whether `CBuilder.library()` from `native_toolchain_c` can compile a minimal C shim from source at build-hook time, linking against a prebuilt `libzenohc.so`, and whether the resulting library can be loaded via `DynamicLibrary.open()`. This is the third experiment in a 2x2 matrix testing Dart build hooks for native library bundling.

### Use Cases
- Validate CBuilder as an alternative to prebuilt library vendoring
- Confirm that `DynamicLibrary.open()` limitation applies regardless of build strategy
- Document CBuilder-specific observations (compile time, header vendoring, RUNPATH)

### Context
A1 (prebuilt + DynamicLibrary.open) produced a NEGATIVE result — `DynamicLibrary.open()` cannot find hook-bundled assets. A2 (prebuilt + @Native) produced a POSITIVE result. B1 tests the CBuilder build strategy with the DynamicLibrary.open() loading mechanism. Based on A1, the expected result is NEGATIVE, confirming the loading mechanism — not the build strategy — is the limiting factor.

CBuilder has a key advantage: it automatically adds `-Wl,-rpath,$ORIGIN` on Linux, eliminating the patchelf requirement that A1/A2 discovered.

---

## Requirements Analysis

### Functional Requirements
1. `hook/build.dart` compiles `zenoh_dart_minimal.c` from source using `CBuilder.library()`
2. `hook/build.dart` declares prebuilt `libzenohc.so` as a `CodeAsset` with `DynamicLoadingBundled()`
3. C source, zenoh-c headers, and Dart API DL files are vendored in the package
4. `lib/src/native_lib.dart` uses `DynamicLibrary.open('libzenoh_dart.so')`
5. `example/smoke.dart` provides a runnable entry point
6. All 6 verification criteria recorded in `lessons-learned.md`

### Non-Functional Requirements
- Code style passes `fvm dart analyze`
- No modifications to `packages/zenoh/` (control package)
- No `LD_LIBRARY_PATH` in any command

### Integration Points
- CBuilder links against vendored `libzenohc.so` at compile time
- CBuilder output feeds into hook's CodeAsset registration
- Results inform experiment B2 (CBuilder + @Native)

---

## Implementation Details

### Architectural Approach
Unlike A1/A2 which vendor prebuilt `.so` files, B1 compiles the C shim from source during the build hook using `CBuilder.library()`. The hook:
1. Invokes CBuilder to compile `zenoh_dart_minimal.c` with vendored headers
2. Links against vendored `libzenohc.so`
3. Registers the compiled library as a CodeAsset
4. Also registers the prebuilt `libzenohc.so` as a second CodeAsset

The loading mechanism (`DynamicLibrary.open()`) is the same as A1, so the expected outcome is the same (negative).

### Design Patterns
- **CBuilder.library()**: Compile-from-source using `native_toolchain_c`
- **Vendored dependencies**: All C sources, headers, and prebuilt zenohc.so are self-contained
- **Graceful degradation**: Tests use `markTestSkipped()` for expected negative results

### File Structure
```
packages/exp_hooks_cbuilder_dlopen/
  pubspec.yaml
  hook/build.dart
  src/
    zenoh_dart_minimal.{h,c}
    dart/dart_api_dl.c
    dart/include/dart_api_dl.h, dart_api.h, dart_native_api.h
  include/                        # vendored zenoh-c headers
  native/linux/x86_64/libzenohc.so
  lib/
    exp_hooks_cbuilder_dlopen.dart
    src/native_lib.dart
  test/
    scaffold_test.dart
    smoke_test.dart
  example/smoke.dart
  lessons-learned.md
```

### Naming Conventions
- Package: `exp_hooks_cbuilder_dlopen` (matrix naming)
- Branch: `experiment/b1-cbuilder-dlopen`

---

## TDD Approach

### Slice Decomposition

4 slices: 3 TDD + 1 post-implementation documentation.

**Test Framework:** `package:test`
**Test Command:** `cd packages/exp_hooks_cbuilder_dlopen && fvm dart test`

### Slice Overview
| # | Slice | Automated Tests | Dependencies |
|---|-------|----------------|-------------|
| 1 | Package scaffold + build hook + vendored sources | 3 | None |
| 2 | DynamicLibrary.open() smoke tests | 5 | Slice 1 |
| 3 | dart run verification | 3 | Slice 2 |
| 4 | CBuilder observations + lessons learned | 0 (docs) | Slices 1-3 |

---

## Dependencies

### External Packages
- `ffi: ^2.1.3`: Dart FFI types
- `hooks: ^1.0.0`: Build hook framework
- `code_assets: ^1.0.0`: CodeAsset declarations
- `native_toolchain_c: ^0.17.5`: CBuilder (EXPERIMENTAL)
- `test: ^1.25.0` (dev): Test framework

### Internal Dependencies
- `extern/zenoh-c/target/release/libzenohc.so`: Prebuilt zenoh-c library (vendored into package)
- `extern/zenoh-c/include/`: zenoh-c headers (vendored into package)
- `src/zenoh_dart.{h,c}`: Reference for minimal C shim (not copied directly)

---

## Known Limitations / Trade-offs

### Limitations
- `native_toolchain_c` is EXPERIMENTAL — may have stability issues
- Linux x86_64 only
- No Flutter test app (criterion 3 = N/A)
- Only tests 2 FFI functions (minimal shim)

### Trade-offs Made
- **Expected negative result accepted**: Same as A1, `DynamicLibrary.open()` likely fails. We test to confirm CBuilder doesn't change the outcome.
- **Vendored sources**: Self-contained package requires copying headers and sources, adding maintenance burden but ensuring reproducibility.
- **Minimal C shim**: Only 2 functions instead of full 62-function shim. Sufficient for mechanism proof.

---

## Implementation Notes

### Key Decisions
- **CBuilder auto-RUNPATH**: CBuilder adds `-Wl,-rpath,$ORIGIN` automatically — no patchelf needed (unlike A1/A2 prebuilt)
- **Spec bug**: Full `package:` URIs in CodeAsset names produce double-prefixed IDs. CI should use bare paths.
- **Merged scaffold + hook**: Single slice for all package creation (A1/A2 lesson)

### Future Improvements
- B2 (CBuilder + @Native) combines CBuilder's build advantage with @Native's resolution advantage
- If B2 succeeds, it represents the ideal end-state: compile from source + automatic asset resolution

### Potential Refactoring
- None anticipated for experiment package (disposable by design)

---

## References

### Related Code
- `packages/exp_hooks_prebuilt_dlopen/` — A1 experiment (DynamicLibrary.open reference)
- `packages/exp_hooks_prebuilt_native/` — A2 experiment (@Native reference)
- `packages/zenoh/lib/src/native_lib.dart` — control package
- `src/zenoh_dart.{h,c}` — full C shim (reference for minimal version)

### Documentation
- `experiments/hooks-bundling/spec-b1-cbuilder-dlopen.md` — experiment specification
- `experiments/hooks-bundling/design.md` — overall experiment design
- `packages/exp_hooks_prebuilt_dlopen/lessons-learned.md` — A1 results
- `packages/exp_hooks_prebuilt_native/lessons-learned.md` — A2 results

### Issues / PRs
- PR #13: Experiment A1 (merged)
- PR #14: Experiment A2 (merged)
