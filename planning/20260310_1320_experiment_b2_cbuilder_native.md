# Feature Notes: Experiment B2 -- CBuilder + @Native Annotations

**Created:** 2026-03-10
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Experiment B2 is the final entry in the 2x2 hooks-bundling experiment matrix. It combines CBuilder's compile-from-source capability (proven in B1) with @Native's asset ID resolution (proven in A2) to achieve the ideal end-state: source-level reproducibility, automatic RUNPATH, and correct asset resolution -- all without `LD_LIBRARY_PATH`.

### Use Cases
- Validate the "best of both worlds" approach for zenoh-dart native bundling
- Confirm CBuilder + @Native as the recommended migration path for `packages/zenoh/`
- Complete the 2x2 experiment matrix for cross-experiment analysis

### Context
Prior experiments established:
- A1 (prebuilt + DynamicLibrary.open) = NEGATIVE -- `DynamicLibrary.open()` can't find hook-bundled assets
- A2 (prebuilt + @Native) = POSITIVE -- `@Native` resolves correctly, but needs patchelf for RUNPATH
- B1 (CBuilder + DynamicLibrary.open) = NEGATIVE -- confirms loading mechanism is the bottleneck
- B2 (CBuilder + @Native) = expected POSITIVE -- combines working build strategy with working loader

B2 eliminates A2's patchelf requirement (CBuilder auto-sets `$ORIGIN` RUNPATH) while keeping A2's @Native resolution.

---

## Requirements Analysis

### Functional Requirements
1. `hook/build.dart` uses `CBuilder.library()` to compile C shim from vendored source
2. `hook/build.dart` declares prebuilt `libzenohc.so` as a separate CodeAsset
3. CBuilder `assetName` matches `@DefaultAsset` URI in `bindings.dart`
4. `lib/src/bindings.dart` uses `@Native` + `@DefaultAsset` -- no DynamicLibrary.open()
5. Tests verify FFI calls without `LD_LIBRARY_PATH`
6. `example/smoke.dart` works without `LD_LIBRARY_PATH`

### Non-Functional Requirements
- Code style passes `fvm dart analyze`
- No modifications to `packages/zenoh/`
- `lessons-learned.md` includes cross-experiment comparison table

### Integration Points
- CBuilder compiles vendored C source at hook time
- CBuilder links against vendored `libzenohc.so`
- @Native resolves the CBuilder output via asset ID mapping
- OS linker resolves `libzenohc.so` via DT_NEEDED + `$ORIGIN` RUNPATH
- Results complete the 2x2 matrix and inform `packages/zenoh/` migration

---

## Implementation Details

### Architectural Approach
B2 = B1's build strategy + A2's loading mechanism. The hook compiles from source using CBuilder (like B1), and the Dart code resolves symbols via @Native annotations (like A2). This is expected to be the optimal configuration since both halves have been individually validated.

Data flow: `hook/build.dart` (CBuilder) → compile `zenoh_dart_minimal.c` → register CodeAsset → `@Native` resolution via asset ID → FFI calls → DT_NEEDED resolves `libzenohc.so` via `$ORIGIN` RUNPATH

### Design Patterns
- **CBuilder.library()**: Compile from vendored source at hook time
- **@Native + @DefaultAsset**: Symbol resolution via Dart runtime asset mapping
- **DT_NEEDED + auto-RUNPATH**: CBuilder sets `$ORIGIN` automatically
- **Graceful degradation**: Tests use `markTestSkipped()` on failure

### File Structure
```
packages/exp_hooks_cbuilder_native/
  pubspec.yaml
  hook/build.dart
  src/
    zenoh_dart_minimal.{h,c}
    dart/dart_api_dl.c
    dart/include/dart_api_dl.h, dart_api.h, dart_native_api.h
  include/                        # vendored zenoh-c headers
  native/linux/x86_64/libzenohc.so
  lib/
    exp_hooks_cbuilder_native.dart
    src/
      bindings.dart               # @DefaultAsset + @Native
      native_lib.dart             # initZenohDart() convenience
  test/
    scaffold_test.dart
    smoke_test.dart
  example/smoke.dart
  lessons-learned.md
```

### Naming Conventions
- Package: `exp_hooks_cbuilder_native` (matrix naming)
- Branch: `experiment/b2-cbuilder-native`

---

## TDD Approach

### Slice Decomposition

3 TDD slices + post-implementation documentation.

**Test Framework:** `package:test`
**Test Command:** `cd packages/exp_hooks_cbuilder_native && fvm dart test`

### Slice Overview
| # | Slice | Automated Tests | Dependencies |
|---|-------|----------------|-------------|
| 1 | Package scaffold + build hook + vendored sources | 4 | None |
| 2 | @Native smoke tests (CBuilder-compiled library) | 4 | Slice 1 |
| 3 | dart run verification + example/smoke.dart | 2 | Slice 2 |

---

## Dependencies

### External Packages
- `ffi: ^2.1.3`: Dart FFI types and @Native support
- `hooks: ^1.0.0`: Build hook framework
- `code_assets: ^1.0.0`: CodeAsset declarations
- `native_toolchain_c: ^0.17.5`: CBuilder (EXPERIMENTAL)
- `test: ^1.25.0` (dev): Test framework

### Internal Dependencies
- B1's vendored files (C source, headers, Dart SDK files) — copy directly
- B1's CBuilder hook — adapt `assetName` for @Native
- A2's @Native bindings — adapt package name
- `extern/zenoh-c/target/release/libzenohc.so`: Prebuilt zenoh-c library

---

## Known Limitations / Trade-offs

### Limitations
- `native_toolchain_c` is EXPERIMENTAL — stability validated in B1 but may change
- Linux x86_64 only
- No Flutter test app (criterion 3 = N/A)
- Only tests 2 FFI functions (minimal shim)

### Trade-offs Made
- **Vendored sources**: Self-contained but adds maintenance burden
- **Minimal C shim**: 2 functions, not full 62-function shim. Sufficient for mechanism proof.
- **Separate bindings.dart and native_lib.dart**: Avoids import issues with `package:ffi/ffi.dart`

---

## Implementation Notes

### Key Decisions
- **B2 = B1 build + A2 load**: Copy from both prior experiments
- **CBuilder auto-RUNPATH**: No patchelf needed (advantage over A2)
- **Separate files for bindings vs convenience**: A2 pattern, avoids import conflicts
- **CodeAsset name alignment**: Must verify CBuilder auto-prefix behavior against @DefaultAsset URI

### Future Improvements
- If B2 succeeds, migrate `packages/zenoh/` to CBuilder + @Native pattern
- Consider CBuilder for full 62-function C shim (not just minimal 2-function)

### Potential Refactoring
- None for experiment package (disposable by design)
- Successful B2 becomes the template for production migration

---

## References

### Related Code
- `packages/exp_hooks_cbuilder_dlopen/` — B1 (CBuilder reference)
- `packages/exp_hooks_prebuilt_native/` — A2 (@Native reference)
- `packages/exp_hooks_prebuilt_dlopen/` — A1 (baseline reference)
- `packages/zenoh/lib/src/native_lib.dart` — control package

### Documentation
- `experiments/hooks-bundling/spec-b2-cbuilder-native.md` — experiment specification
- `experiments/hooks-bundling/design.md` — overall experiment design
- `packages/exp_hooks_cbuilder_dlopen/lessons-learned.md` — B1 results
- `packages/exp_hooks_prebuilt_native/lessons-learned.md` — A2 results
- `packages/exp_hooks_prebuilt_dlopen/lessons-learned.md` — A1 results

### Issues / PRs
- PR #13: Experiment A1 (merged)
- PR #14: Experiment A2 (merged)
- PR #15: Experiment B1 (merged)
