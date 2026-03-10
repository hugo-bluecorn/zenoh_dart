# Experiment A1: Prebuilt + DynamicLibrary.open() -- Lessons Learned

## Summary

`DynamicLibrary.open('libzenoh_dart.so')` does NOT find hook-bundled native
libraries. The Dart build hook runs successfully and registers the assets in
`.dart_tool/hooks_runner/` metadata, but `DynamicLibrary.open()` uses the OS
dynamic linker (ld.so) search path, which does not include the hook output
directory. The hook's `DynamicLoadingBundled()` link mode is designed for
`@Native` asset resolution, not `DynamicLibrary.open()`.

## Verification Criteria

### 1. Build hook runs without errors

**Result: PASS**

The hook runs successfully on both `dart run` and `dart test`. The
"Running build hooks..." message appears in output. The hook output metadata
at `.dart_tool/hooks_runner/exp_hooks_prebuilt_dlopen/<hash>/output.json`
confirms `"status": "success"` with both assets registered:

```json
{
  "assets": [
    {
      "encoding": {
        "file": ".../native/linux/x86_64/libzenoh_dart.so",
        "id": "package:exp_hooks_prebuilt_dlopen/src/native_lib.dart",
        "link_mode": { "type": "dynamic_loading_bundle" }
      },
      "type": "code_assets/code"
    },
    {
      "encoding": {
        "file": ".../native/linux/x86_64/libzenohc.so",
        "id": "package:exp_hooks_prebuilt_dlopen/src/libzenohc.dart",
        "link_mode": { "type": "dynamic_loading_bundle" }
      },
      "type": "code_assets/code"
    }
  ],
  "status": "success"
}
```

### 2. Native libraries are bundled with the application

**Result: PARTIAL PASS**

The hook declares assets with `DynamicLoadingBundled()` and points to the
prebuilt `.so` files in `native/linux/x86_64/`. The metadata is written, but the
files are NOT copied to any runtime-accessible location. The hook output merely
records the source file paths -- actual bundling (copying to an output directory
on the linker search path) is handled by the Dart/Flutter tooling only for
`@Native` asset resolution, not for `DynamicLibrary.open()`.

### 3. DynamicLibrary.open() finds the bundled libraries

**Result: FAIL**

```
$ cd packages/exp_hooks_prebuilt_dlopen && fvm dart run example/smoke.dart

Running build hooks...Running build hooks...Unhandled exception:
Invalid argument(s): Failed to load dynamic library 'libzenoh_dart.so':
  libzenoh_dart.so: cannot open shared object file: No such file or directory
#0      _open (dart:ffi-patch/ffi_dynamic_library_patch.dart:11:43)
#1      new DynamicLibrary.open (dart:ffi-patch/ffi_dynamic_library_patch.dart:22:12)
#2      initZenohDart (package:exp_hooks_prebuilt_dlopen/src/native_lib.dart:18:30)
#3      main (file://.../example/smoke.dart:4:18)
```

Exit code: 255.

**Control test** (with LD_LIBRARY_PATH): Succeeds, confirming the libraries
themselves are valid.

```
$ LD_LIBRARY_PATH=native/linux/x86_64 fvm dart run example/smoke.dart
Running build hooks...Running build hooks...initZenohDart() returned: true
```

### 4. FFI calls through the loaded library work correctly

**Result: FAIL (blocked by Criterion 3)**

Since `DynamicLibrary.open()` cannot find the library, no FFI calls can be made.
When the library IS loaded via `LD_LIBRARY_PATH`, FFI calls work correctly
(`zd_init_dart_api_dl` returns 0, `zd_init_log` completes without error).

### 5. dart test can load and use the native libraries

**Result: FAIL (negative result -- all smoke tests skipped)**

```
$ cd packages/exp_hooks_prebuilt_dlopen && fvm dart test

00:00 +2 ~5: All tests passed!
```

The test suite exits 0, but 5 of 7 tests are skipped because `DynamicLibrary.open`
fails. Only the 2 scaffold tests (barrel export check, workspace resolution) pass.
The smoke tests correctly detect the failure and mark themselves as skipped with
informative messages:

```
DynamicLibrary.open cannot find hook-bundled assets: Failed to load dynamic
library 'libzenoh_dart.so': libzenoh_dart.so: cannot open shared object file:
No such file or directory
```

**Control test** (with LD_LIBRARY_PATH): All 7 tests pass, 0 skipped.

### 6. dart run can load and use the native libraries

**Result: FAIL (see Criterion 3)**

`dart run` triggers the build hook (confirmed by "Running build hooks..."
output), but the hook-registered assets are not placed on the OS dynamic linker
search path. The `DynamicLibrary.open('libzenoh_dart.so')` call fails with
"cannot open shared object file: No such file or directory".

## Unexpected Findings

### 1. RUNPATH is hardcoded to the build machine's absolute path

`readelf -d` on the prebuilt `libzenoh_dart.so` shows:

```
RUNPATH: /home/hugo-bluecorn/bluecorn/CSR/git/zenoh_dart/extern/zenoh-c/target/release
```

This is the developer build path baked in by CMake. In the control test (with
`LD_LIBRARY_PATH`), `libzenohc.so` resolves via `LD_LIBRARY_PATH` which takes
precedence over RUNPATH. In a deployed scenario, this RUNPATH would be useless.
The CMakeLists.txt sets `$ORIGIN` RPATH, but the prebuilt copy in
`native/linux/x86_64/` retains the build-time RUNPATH. For proper deployment,
the prebuilt `.so` should be rebuilt with `$ORIGIN` RPATH or patched with
`patchelf --set-rpath '$ORIGIN'`.

### 2. Hook metadata records source paths, not output paths

The hook output JSON records the absolute path to the source `.so` files in the
package's `native/` directory. There is no copying or symlinking step. The Dart
tooling uses this metadata only for `@Native` annotation asset resolution (which
reads the metadata and loads the file directly), not for `DynamicLibrary.open()`
(which delegates entirely to ld.so).

### 3. Build hooks run twice

Both `dart run` and `dart test` print "Running build hooks..." twice. This
appears to be the hook system running the build hook for each package that
declares hooks in the dependency graph. This is cosmetic but worth noting for
performance considerations in larger dependency trees.

## Recommendations

### For Experiment A2 (@Native annotations)

1. **Replace `DynamicLibrary.open()` with `@Native` annotations.** The `@Native`
   asset resolution system reads the hook output metadata and loads the library
   by its asset ID (`package:exp_hooks_prebuilt_dlopen/src/native_lib.dart`).
   This is the intended loading mechanism for hook-bundled assets.

2. **Use `@DefaultAsset` on the library-level declaration** to set the default
   asset ID, then individual `@Native` annotations on external function
   declarations. This eliminates the need for `DynamicLibrary.open()` entirely.

3. **Test both `dart run` and `dart test` without LD_LIBRARY_PATH** to confirm
   that `@Native` resolution finds the hook-bundled assets via the metadata
   path.

### For the DT_NEEDED dependency chain

4. **Verify how `@Native` handles transitive dependencies.** When the Dart
   tooling loads `libzenoh_dart.so` via its asset ID, the OS linker still needs
   to resolve the `DT_NEEDED` dependency on `libzenohc.so`. Experiment A2 must
   verify that registering `libzenohc.so` as a separate code asset (with its own
   asset ID) is sufficient for the OS linker to find it, or whether RPATH
   patching is needed.

5. **Fix the RUNPATH in prebuilt libraries.** Before A2, run
   `patchelf --set-rpath '$ORIGIN' native/linux/x86_64/libzenoh_dart.so` so that
   `libzenohc.so` is found relative to `libzenoh_dart.so` when both are in the
   same directory.

### General

6. **`DynamicLibrary.open()` is incompatible with Dart build hooks** for
   library discovery. This is the key finding of A1. Any project migrating to
   build hooks must also migrate to `@Native` annotations (or use
   `DynamicLibrary.open()` with a full path obtained from the asset resolver
   API, if such an API exists).
