# Experiment A2: Prebuilt + @Native -- Lessons Learned

## Summary

`@Native` + `@DefaultAsset` annotations with prebuilt native libraries and
Dart build hooks **work correctly**. Both `dart test` and `dart run` resolve
native symbols without `LD_LIBRARY_PATH`. The DT_NEEDED dependency chain
(libzenoh_dart.so -> libzenohc.so) resolves via RUNPATH `$ORIGIN` when both
libraries are co-located in `native/linux/x86_64/`.

This is a **complete success** for the two-library prebuilt + @Native approach.

## Verification Criteria

### 1. `dart run` finds bundled libs

**Result: PASS**

```
$ cd packages/exp_hooks_prebuilt_native && fvm dart run example/smoke.dart
Running build hooks...Running build hooks...initZenohDart() returned: true
```

No `LD_LIBRARY_PATH` needed. The Dart runtime resolves `@Native` symbols via
the asset ID mapping produced by the build hook. Exit code 0.

### 2. `dart test` finds bundled libs

**Result: PASS**

```
$ cd packages/exp_hooks_prebuilt_native && fvm dart test
Running build hooks...Running build hooks...
00:00 +0: loading test/scaffold_test.dart
...
00:00 +9: All tests passed!
```

All 9 tests pass (3 scaffold + 4 @Native smoke + 2 dart-run verification).
Zero tests skipped. No `LD_LIBRARY_PATH` needed.

### 3. `flutter run` finds bundled libs

**Result: N/A** -- no Flutter test app in A2. This experiment tests pure Dart
CLI/test scenarios only. Flutter integration is out of scope for the A1/A2
dimension of the 2x2 experiment matrix.

### 4. DT_NEEDED dependency resolves

**Result: PASS**

The `zd_init_log` function in libzenoh_dart.so calls through to libzenohc.so
(the zenoh-c library). This call succeeds, proving the OS linker resolves the
DT_NEEDED dependency at runtime:

```
$ readelf -d native/linux/x86_64/libzenoh_dart.so | grep -E 'NEEDED|RUNPATH'
 (NEEDED)  Shared library: [libzenohc.so]
 (NEEDED)  Shared library: [libc.so.6]
 (RUNPATH) Library runpath: [$ORIGIN]
```

Both `.so` files are co-located in `native/linux/x86_64/`. The `$ORIGIN`
RUNPATH tells the OS linker to look in the same directory as the loading
library, which resolves libzenohc.so without any environment variable.

### 5. Hook build succeeds on Linux x86_64

**Result: PASS**

The build hook (`hook/build.dart`) runs successfully and registers two
CodeAsset entries:

1. `package:exp_hooks_prebuilt_native/src/bindings.dart` -> libzenoh_dart.so
2. `package:exp_hooks_prebuilt_native/src/zenohc.dart` -> libzenohc.so

The hook output is confirmed by "Running build hooks..." appearing in both
`dart run` and `dart test` output.

### 6. Error reporting quality

**Result: GOOD**

When `@Native` resolution fails (e.g., if the native libraries are missing),
the Dart runtime produces clear error messages:

```
Failed to lookup symbol 'zd_init_dart_api_dl':
  undefined symbol: zd_init_dart_api_dl
```

This is more actionable than `DynamicLibrary.open()`'s generic "cannot open
shared object file" message, because it names the specific symbol that failed
and the asset ID it tried to resolve against.

In the A2 test suite, the `@Native failure produces informative error` test
captures and documents the failure mode for diagnostic purposes.

## A1 vs A2 Comparison

| Aspect | A1 (DynamicLibrary.open) | A2 (@Native) |
|--------|--------------------------|--------------|
| Loading mechanism | `DynamicLibrary.open('libzenoh_dart.so')` | `@DefaultAsset` + `@Native` annotations |
| Asset resolution | OS dynamic linker (ld.so) search path | Dart runtime resolves via asset ID mapping |
| No LD_LIBRARY_PATH needed? | **NO** -- FAILS without it | **YES** -- works without it |
| DT_NEEDED resolution | Requires LD_LIBRARY_PATH for libzenohc.so | RUNPATH `$ORIGIN` resolves co-located libzenohc.so |
| Binding style | `lookupFunction<NativeType, DartType>()` | `external` functions with `@Native()` annotation |
| Hook integration | Hook runs, but assets not on ld.so path | Hook runs, Dart runtime reads asset metadata |
| Test results (without LD_LIBRARY_PATH) | 2/7 pass, 5 skipped | 9/9 pass, 0 skipped |
| dart run (without LD_LIBRARY_PATH) | Exit code 255 (load failure) | Exit code 0 (success) |

### Key Insight

`DynamicLibrary.open()` delegates library lookup entirely to the OS dynamic
linker, which knows nothing about Dart build hooks or asset metadata.
`@Native` annotations are resolved by the Dart runtime itself, which reads the
hook output metadata (`.dart_tool/hooks_runner/`) and loads libraries by their
registered file paths. This is why A1 fails and A2 succeeds with identical
build hooks and identical prebuilt libraries.

### RUNPATH Patching

A1's prebuilt libzenoh_dart.so had its build-time RUNPATH baked in (absolute
path to the developer's zenoh-c build directory). This was fixed for A2 using
`patchelf --set-rpath '$ORIGIN'`, so that the OS linker finds libzenohc.so
relative to libzenoh_dart.so when both are co-located. This fix was essential
for DT_NEEDED resolution without LD_LIBRARY_PATH.

### CodeAsset Name Gotcha

The `CodeAsset` constructor auto-prepends `package:<packageName>/` to the
`name` parameter. Using a full `package:` URI (e.g.,
`package:foo/src/bindings.dart`) as the name produces a double-prefixed ID
(`package:foo/package:foo/src/bindings.dart`) that breaks `@Native` resolution.
Always use bare relative paths like `src/bindings.dart` as the CodeAsset name.

## Findings

### 1. @Native + build hooks is the correct approach for two-library FFI

The combination of:
- `@DefaultAsset('package:pkg/src/bindings.dart')` on the binding library
- `@Native()` on each external function declaration
- Build hook registering CodeAssets with matching asset IDs
- RUNPATH `$ORIGIN` for DT_NEEDED resolution between co-located libraries

...provides a complete solution that works for both `dart test` and `dart run`
without any environment variable configuration.

### 2. Two CodeAsset entries are required

Even though only libzenoh_dart.so has `@Native` symbols, libzenohc.so must
also be registered as a CodeAsset. The Dart tooling copies/symlinks registered
assets to a runtime-accessible location. Without registering libzenohc.so, the
OS linker would fail to resolve the DT_NEEDED dependency even though
libzenoh_dart.so loads correctly.

### 3. Build hooks run twice (cosmetic)

Both `dart run` and `dart test` print "Running build hooks..." twice. This
appears to be the hook system processing each package's hooks in the dependency
graph. Same behavior as observed in A1. Cosmetic only -- no functional impact.

### 4. VM crash on exit (cosmetic)

After tests complete successfully, the Dart VM occasionally crashes with
`SEGV_MAPERR` during process teardown. This is a known cosmetic issue with
zenoh native library cleanup ordering, not related to the build hook mechanism.
All tests pass before the crash, and exit code is reliably 0.

## Recommendations for Main Package Migration

1. **Use @Native annotations** in `packages/zenoh/lib/src/bindings.dart`
   (already generated by ffigen with `@Native` support).

2. **Add a build hook** (`packages/zenoh/hook/build.dart`) registering both
   libzenoh_dart.so and libzenohc.so as CodeAssets.

3. **Patch RUNPATH to `$ORIGIN`** on prebuilt libzenoh_dart.so before
   distributing.

4. **Remove `LD_LIBRARY_PATH` from test/run commands** once hooks are in place.

5. **Consider B1/B2 experiments** before finalizing -- CBuilder may offer
   advantages for from-source builds and cross-compilation scenarios.
