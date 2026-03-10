# Experiment B2: CBuilder + @Native -- Lessons Learned

## Summary

**Result: POSITIVE** -- CBuilder compilation + `@Native` annotations work
correctly. Both `dart test` and `dart run` resolve native symbols without
`LD_LIBRARY_PATH`. CBuilder automatically sets RUNPATH to `$ORIGIN`, resolving
the DT_NEEDED dependency (libzenoh_dart.so -> libzenohc.so) without any manual
patchelf step.

This completes the 2x2 experiment matrix with a clear conclusion: **@Native is
the sole determinant of success**. Build strategy (prebuilt vs CBuilder) is
irrelevant to runtime asset resolution.

## Verification Criteria

### 1. `dart run` finds bundled libs

**Result: PASS**

```
$ cd packages/exp_hooks_cbuilder_native && fvm dart run example/smoke.dart
Running build hooks...Running build hooks...initZenohDart() returned: true
```

No `LD_LIBRARY_PATH` needed. Exit code 0. The Dart runtime resolves `@Native`
symbols via the asset ID mapping produced by the build hook.

### 2. `dart test` finds bundled libs

**Result: PASS**

```
$ cd packages/exp_hooks_cbuilder_native && fvm dart test
Running build hooks...Running build hooks...
00:00 +10: All tests passed!
```

All 10 tests pass (4 scaffold + 4 @Native smoke + 2 dart-run verification).
Zero tests skipped. No `LD_LIBRARY_PATH` needed.

### 3. `flutter run` finds bundled libs

**Result: N/A** -- no Flutter test app in B2. Pure Dart CLI/test only.

### 4. DT_NEEDED dependency resolves

**Result: PASS**

The `zd_init_log` function in libzenoh_dart.so calls through to libzenohc.so.
This call succeeds, proving the OS linker resolves the DT_NEEDED dependency:

```
$ readelf -d .dart_tool/lib/libzenoh_dart.so | grep -E 'NEEDED|RUNPATH'
 (NEEDED)  Shared library: [libzenohc.so]
 (NEEDED)  Shared library: [libc.so.6]
 (RUNPATH) Library runpath: [$ORIGIN]
```

CBuilder sets RUNPATH to `$ORIGIN` automatically -- no patchelf needed (unlike
the prebuilt approach A2 which required manual RUNPATH patching).

### 5. Hook build succeeds on Linux x86_64

**Result: PASS**

CBuilder compiles the C shim from vendored source and registers two CodeAsset
entries. The hook output is confirmed by "Running build hooks..." appearing in
both `dart run` and `dart test` output.

### 6. Error reporting quality

**Result: N/A (positive result)** -- no errors observed during normal operation.
When @Native resolution fails (e.g., missing libraries), the Dart runtime
produces clear symbol-level error messages (same as A2).

## Cross-Experiment Comparison (Full 2x2 Matrix)

| | DynamicLibrary.open() | @Native |
|---|---|---|
| **Prebuilt** | A1: **NEGATIVE** | A2: **POSITIVE** |
| **CBuilder** | B1: **NEGATIVE** | B2: **POSITIVE** |

### Detailed Comparison

| Aspect | A1 (Prebuilt+DLOpen) | A2 (Prebuilt+@Native) | B1 (CBuilder+DLOpen) | B2 (CBuilder+@Native) |
|--------|----------------------|------------------------|----------------------|------------------------|
| **Overall result** | NEGATIVE | POSITIVE | NEGATIVE | POSITIVE |
| Build strategy | Prebuilt copy | Prebuilt copy | CBuilder from source | CBuilder from source |
| Loading mechanism | DynamicLibrary.open | @Native annotations | DynamicLibrary.open | @Native annotations |
| Hook build | PASS | PASS | PASS | PASS |
| Asset registration | PASS | PASS | PASS | PASS |
| Library loading | FAIL | PASS | FAIL | PASS |
| DT_NEEDED | Blocked | PASS | Blocked | PASS |
| Tests (no LD_LIBRARY_PATH) | 2/7 pass, 5 skip | 9/9 pass | 6/11 pass, 5 skip | 10/10 pass |
| dart run (no LD_LIBRARY_PATH) | FAIL (exit 255) | PASS (exit 0) | FAIL (exit 1) | PASS (exit 0) |
| RUNPATH | Build-time absolute | `$ORIGIN` (patchelf'd) | `$ORIGIN` (automatic) | `$ORIGIN` (automatic) |
| Cold build time | ~0.3s (copy) | ~0.3s (copy) | ~1.0s (compile) | ~1.0s (compile) |
| Warm build time | ~0.3s | ~0.3s | ~0.3s | ~0.3s |
| Header vendoring | None | None | 15 files | 15 files |
| Lines of Dart code | 67 | 68 | 77 | 75 |
| Error message on failure | OS ld.so error | Dart symbol resolution | OS ld.so error | Dart symbol resolution |

### Key Insight

**The loading mechanism (@Native vs DynamicLibrary.open) is the sole
determinant of success or failure.** Build strategy is irrelevant.

- `DynamicLibrary.open()` delegates to the OS dynamic linker (`ld.so`), which
  does not consult Dart build hook metadata. It fails regardless of whether
  libraries are prebuilt (A1) or CBuilder-compiled (B1).
- `@Native` annotations are resolved by the Dart runtime, which reads the hook
  output metadata (`.dart_tool/hooks_runner/`) and loads libraries by their
  registered file paths. It succeeds regardless of build strategy (A2, B2).

## CBuilder-Specific Observations

### 1. Automatic RUNPATH

CBuilder sets RUNPATH to `$ORIGIN` automatically via native_toolchain_c. This
eliminates the patchelf step required by the prebuilt approach. For a
two-library project like zenoh-dart (libzenoh_dart.so + libzenohc.so), this is
a significant DX improvement.

### 2. Header vendoring overhead

B2 requires 15 vendored files (8 zenoh-c headers + 6 Dart SDK files + 1
project header). These must be kept in sync with upstream versions when
upgrading zenoh-c or the Dart SDK. The prebuilt approach (A2) has zero vendoring
overhead.

### 3. native_toolchain_c stability

Version 0.17.5 compiled the C shim without issues. Despite its "EXPERIMENTAL"
status, it worked reliably for this use case. It correctly found the system C
compiler, passed include/link flags, tracked dependencies, and set RUNPATH.

### 4. Build hooks run twice (cosmetic)

Same behavior as all other experiments -- "Running build hooks..." printed
twice. Cosmetic only.

### 5. VM crash on exit (cosmetic)

After tests complete successfully, the Dart VM occasionally crashes with
`SEGV_MAPERR` during process teardown. This is a known cosmetic issue with
zenoh native library cleanup ordering, not related to the build hook mechanism.
All tests pass before the crash.

## Recommendation for packages/zenoh/ Migration

Based on all 4 experiments:

1. **Use @Native annotations** -- mandatory. DynamicLibrary.open() does not
   work with build hooks. This is the single most important finding.

2. **Start with prebuilt approach (A2-style)** for the initial migration:
   - Faster builds (no compilation step)
   - No header vendoring
   - Simpler hook (just copy prebuilt .so files)
   - Requires one-time `patchelf --set-rpath '$ORIGIN'` on prebuilt libraries

3. **Consider CBuilder (B2-style) for CI/CD and distribution**:
   - Automatic RUNPATH (no patchelf)
   - Source-level reproducibility
   - Cross-compilation potential (NDK for Android)
   - But adds ~0.7s cold build overhead and header vendoring burden

4. **Both approaches require two CodeAsset registrations** -- one for
   libzenoh_dart.so (with @Native symbol bindings) and one for libzenohc.so
   (for DT_NEEDED resolution via co-location).

5. **Remove LD_LIBRARY_PATH from all test/run commands** once hooks are in
   place. The hook system handles library discovery entirely.

### Migration path

```
Phase 1: Add @Native annotations to packages/zenoh/ (ffigen already supports this)
Phase 2: Add hook/build.dart with prebuilt strategy (A2-style)
Phase 3: Remove LD_LIBRARY_PATH from CLAUDE.md, README.md, CI
Phase 4: (Optional) Switch to CBuilder for from-source builds
```
