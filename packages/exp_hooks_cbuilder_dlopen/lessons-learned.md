# Experiment B1: CBuilder + DynamicLibrary.open() -- Lessons Learned

## Summary

**Result: NEGATIVE** -- `DynamicLibrary.open('libzenoh_dart.so')` cannot find
CBuilder-compiled native libraries, exactly as predicted. The loading mechanism
(DynamicLibrary.open vs @Native) is the independent variable that determines
success or failure. The build strategy (prebuilt vs CBuilder) is irrelevant to
asset discovery at runtime.

CBuilder itself works correctly: it compiles the C shim from vendored source,
links against the prebuilt libzenohc.so, sets RUNPATH to `$ORIGIN`, and
produces a valid shared library. The failure is strictly in the loading path --
the OS dynamic linker (ld.so) does not consult Dart build hook metadata.

## Verification Criteria

### Criterion 1: `dart run` finds bundled libs

**Result: FAIL**

```
$ cd packages/exp_hooks_cbuilder_dlopen && fvm dart run example/smoke.dart

Running build hooks...Running build hooks...initZenohDart() failed:
Invalid argument(s): Failed to load dynamic library 'libzenoh_dart.so':
  libzenoh_dart.so: cannot open shared object file: No such file or directory
```

Exit code 1. The build hook runs successfully (CBuilder compiles the shim),
but `DynamicLibrary.open('libzenoh_dart.so')` fails because the compiled
library is placed in `.dart_tool/hooks_runner/shared/exp_hooks_cbuilder_dlopen/
build/<hash>/` which is not on the ld.so search path.

**Control test** (with LD_LIBRARY_PATH pointing to CBuilder output + prebuilt):

```
$ LD_LIBRARY_PATH=.dart_tool/lib fvm dart run example/smoke.dart
Running build hooks...Running build hooks...initZenohDart() returned: true
```

### Criterion 2: `dart test` finds bundled libs

**Result: PASS (tests pass, smoke tests skipped with negative result)**

```
$ cd packages/exp_hooks_cbuilder_dlopen && fvm dart test

Running build hooks...Running build hooks...
00:01 +6 ~5: All tests passed!
```

6 tests pass, 5 smoke tests skipped. The smoke tests correctly detect the
`DynamicLibrary.open` failure and mark themselves as skipped with informative
messages:

```
DynamicLibrary.open cannot find CBuilder output: Failed to load dynamic
library 'libzenoh_dart.so': libzenoh_dart.so: cannot open shared object
file: No such file or directory
```

The 3 passing non-skipped tests are: scaffold barrel export, workspace
resolution, pubspec dependency check, dart-run hook invocation, dart-run
outcome, and dart-run LD_LIBRARY_PATH control.

### Criterion 3: `flutter run` finds bundled libs

**Result: N/A** -- no Flutter test app in B1.

### Criterion 4: DT_NEEDED dependency resolves

**Result: BLOCKED by Criterion 1 (DynamicLibrary.open failure)**

Since `DynamicLibrary.open()` cannot find the CBuilder-compiled library, the
DT_NEEDED chain is never exercised in the default path.

**Control test confirms DT_NEEDED works when ld.so can find both libraries:**

```
$ readelf -d .dart_tool/hooks_runner/shared/.../libzenoh_dart.so | grep -E 'NEEDED|RUNPATH'
 (NEEDED)  Shared library: [libzenohc.so]
 (NEEDED)  Shared library: [libc.so.6]
 (RUNPATH) Library runpath: [$ORIGIN]
```

With `LD_LIBRARY_PATH` set, `zd_init_log` (which calls through to libzenohc.so
via `zc_init_log_from_env_or`) completes successfully. DT_NEEDED resolution
itself is not the problem.

### Criterion 5: Hook build succeeds on Linux x86_64

**Result: PASS**

CBuilder compiles the C shim from source successfully. The hook output metadata
at `.dart_tool/hooks_runner/exp_hooks_cbuilder_dlopen/<hash>/output.json`
confirms `"status": "success"` with both assets registered:

```json
{
  "assets": [
    {
      "encoding": {
        "file": ".../build/<hash>/libzenoh_dart.so",
        "id": "package:exp_hooks_cbuilder_dlopen/src/native_lib.dart",
        "link_mode": { "type": "dynamic_loading_bundle" }
      },
      "type": "code_assets/code"
    },
    {
      "encoding": {
        "file": ".../native/linux/x86_64/libzenohc.so",
        "id": "package:exp_hooks_cbuilder_dlopen/src/zenohc.dart",
        "link_mode": { "type": "dynamic_loading_bundle" }
      },
      "type": "code_assets/code"
    }
  ],
  "status": "success"
}
```

The compiled `.so` exists at the CBuilder output path:

```
$ file .dart_tool/hooks_runner/shared/.../libzenoh_dart.so
ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked,
BuildID[sha1]=f7957aa..., not stripped
```

Size: 22,000 bytes (vs the prebuilt libzenoh_dart.so from the main project
which is ~400KB with all 62 C shim functions -- this minimal shim has only 2).

### Criterion 6: Error reporting quality

**Result: SAME AS A1 -- OS-level error message**

```
Failed to load dynamic library 'libzenoh_dart.so':
  libzenoh_dart.so: cannot open shared object file: No such file or directory
```

This is the standard ld.so error message, identical to A1. It names the library
but gives no hint about build hooks or asset IDs. It does not tell the developer
that `@Native` annotations would solve the problem.

## CBuilder-Specific Observations

### 1. Compilation time

**Cold cache (first build):** ~1.0 second for the minimal 2-function C shim.

```
real  0m1.021s
user  0m0.988s
sys   0m0.284s
```

**Warm cache (no source changes):** ~0.3 seconds (hook skips recompilation).

```
real  0m0.304s
user  0m0.305s
sys   0m0.099s
```

For a minimal shim (2 functions, 2 source files), this is fast. The full
zenoh_dart C shim (62 functions, single source file) would take longer but
likely still under 5 seconds. This is acceptable for development iteration.

Compared to the prebuilt approach (A1), there is a ~0.7s overhead on cold
builds. On warm builds, the difference is negligible (hook cache detection
dominates both approaches).

### 2. Header vendoring friction

**15 files vendored total:**

- 8 zenoh-c headers in `include/`: zenoh.h, zenoh_commons.h, zenoh_concrete.h,
  zenoh_configure.h, zenoh_constants.h, zenoh_macros.h, zenoh_memory.h,
  zenoh_opaque.h
- 6 Dart SDK files in `src/dart/`: dart_api_dl.c, dart_api_dl.h, plus
  `include/` subdirectory with dart_api.h, dart_native_api.h, dart_version.h,
  internal/dart_api_dl_impl.h
- 1 project header: src/zenoh_dart_minimal.h

**Friction level: MODERATE.** The zenoh-c headers are straightforward to copy
from `extern/zenoh-c/include/`. The Dart SDK headers require knowing the
correct path (`<dart-sdk>/include/`) and the internal/ subdirectory structure.
Both sets must be kept in sync with their upstream versions when upgrading.

The hook output metadata (`output.json`) correctly tracks all 15 files as
dependencies, meaning CBuilder will recompile if any header changes.

**No transitive include issues.** zenoh.h includes all other zenoh_*.h headers,
and all are present in the vendored `include/` directory. The Dart SDK headers
are self-contained within `src/dart/`.

### 3. native_toolchain_c stability

**No issues encountered.** Version 0.17.5 (the latest available) compiled the
C shim without errors or warnings. The CBuilder API is straightforward:

```dart
CBuilder.library(
  name: 'zenoh_dart',
  assetName: 'src/native_lib.dart',
  sources: ['src/zenoh_dart_minimal.c', 'src/dart/dart_api_dl.c'],
  includes: ['include', 'src/dart', 'src/dart/include'],
  libraries: ['zenohc'],
  flags: ['-L${packageRoot.resolve("native/linux/x86_64/").toFilePath()}'],
);
```

Despite the "EXPERIMENTAL" status of native_toolchain_c, it worked reliably
for this use case. It correctly:
- Found the system C compiler (clang)
- Passed include paths to the compiler
- Passed -L and -l flags to the linker
- Set RUNPATH to `$ORIGIN` automatically
- Tracked source and header dependencies for cache invalidation

### 4. RUNPATH behavior

**CBuilder automatically sets RUNPATH to `$ORIGIN`:**

```
$ readelf -d .dart_tool/hooks_runner/shared/.../libzenoh_dart.so | grep RUNPATH
 (RUNPATH) Library runpath: [$ORIGIN]
```

This is a significant advantage over the prebuilt approach (A1), where the
developer-built libzenoh_dart.so had the build machine's absolute path baked
into RUNPATH. CBuilder produces deployment-ready RUNPATH out of the box,
eliminating the need for post-build `patchelf --set-rpath '$ORIGIN'`.

### 5. CBuilder output location

CBuilder places the compiled library at:

```
.dart_tool/hooks_runner/shared/exp_hooks_cbuilder_dlopen/build/<hash>/libzenoh_dart.so
```

The `<hash>` is deterministic based on the build configuration (same hash
`6b4ebf10e7` across runs). The shared library is 22KB (minimal shim).

There is also a copy at `.dart_tool/lib/libzenoh_dart.so` (22KB) alongside
`.dart_tool/lib/libzenohc.so` (14.6MB). These appear to be copies placed by
a prior setup step, not by CBuilder itself.

### 6. Link flags

Link flags are passed through the CBuilder API:

- **`libraries: ['zenohc']`** -- translates to `-lzenohc` linker flag
- **`flags: ['-L<path>']`** -- provides the library search path at link time

The `-L` flag uses `packageRoot.resolve(...)` to compute an absolute path to
the `native/linux/x86_64/` directory containing the prebuilt libzenohc.so.
At runtime, the RUNPATH `$ORIGIN` means libzenohc.so must be co-located with
libzenoh_dart.so (which is handled by registering both as CodeAssets in the
hook).

## A1 / A2 / B1 Comparison

| Aspect | A1 (Prebuilt+DLOpen) | A2 (Prebuilt+@Native) | B1 (CBuilder+DLOpen) |
|--------|----------------------|------------------------|----------------------|
| Build strategy | Prebuilt copy | Prebuilt copy | CBuilder from source |
| Loading mechanism | DynamicLibrary.open | @Native annotations | DynamicLibrary.open |
| **Overall result** | **NEGATIVE** | **POSITIVE** | **NEGATIVE** |
| Hook build | PASS | PASS | PASS |
| Asset registration | PASS | PASS | PASS |
| Library loading | FAIL | PASS | FAIL |
| DT_NEEDED | Blocked | PASS | Blocked |
| Tests (no LD_LIBRARY_PATH) | 2/7 pass, 5 skip | 9/9 pass | 6/11 pass, 5 skip |
| dart run (no LD_LIBRARY_PATH) | FAIL (exit 255) | PASS (exit 0) | FAIL (exit 1) |
| RUNPATH | Build-time absolute path | `$ORIGIN` (patchelf'd) | `$ORIGIN` (automatic) |
| Cold build time | ~0.3s (copy only) | ~0.3s (copy only) | ~1.0s (compilation) |
| Warm build time | ~0.3s | ~0.3s | ~0.3s |
| Header vendoring | None needed | None needed | 15 files (8 zenoh-c + 6 Dart SDK + 1 project) |
| Error message | OS ld.so error | Dart symbol resolution | OS ld.so error |

### Key Insight

**The loading mechanism is the independent variable.** Both A1 and B1 fail with
identical symptoms despite using completely different build strategies (prebuilt
copy vs CBuilder compilation). Both A2 (prebuilt + @Native) succeeds where A1
fails, despite identical build hooks and libraries. This confirms the 2x2
experiment hypothesis:

- `DynamicLibrary.open()` delegates to the OS dynamic linker, which does not
  consult Dart build hook metadata. It fails regardless of build strategy.
- `@Native` annotations are resolved by the Dart runtime, which reads the hook
  output metadata and loads libraries by their registered file paths. It
  succeeds regardless of build strategy.

### CBuilder Advantages (for B2)

Despite B1's loading failure, CBuilder offers tangible benefits over prebuilt:

1. **Automatic `$ORIGIN` RUNPATH** -- no patchelf step needed (A1/A2 required
   manual RUNPATH patching).
2. **Source-level reproducibility** -- library is compiled from vendored source,
   not a binary blob. Build is deterministic.
3. **Cross-compilation potential** -- CBuilder integrates with NDK toolchains
   for Android, which prebuilt requires pre-compiled per-ABI binaries.
4. **Dependency tracking** -- CBuilder tracks all 15 source/header files and
   recompiles only when they change.

These advantages will carry over to B2 (CBuilder + @Native), which is expected
to produce a POSITIVE result based on the A1/A2 pattern.

## Unexpected Findings

### 1. CBuilder output hash is deterministic

The build output directory uses hash `6b4ebf10e7` consistently across cache
clears and rebuilds. This hash appears to be derived from the build
configuration (sources, flags, includes) rather than from timestamps.

### 2. Hook dependencies list is comprehensive

The hook output metadata lists all 15 source and header files as dependencies:

```json
"dependencies": [
  ".../src/zenoh_dart_minimal.c",
  ".../src/dart/dart_api_dl.c",
  ".../include/zenoh_concrete.h",
  ".../include/zenoh_opaque.h",
  ".../include/zenoh_constants.h",
  ".../include/zenoh_macros.h",
  ".../include/zenoh_commons.h",
  ".../include/zenoh.h",
  ".../include/zenoh_memory.h",
  ".../include/zenoh_configure.h",
  ".../src/dart/dart_api_dl.h",
  ".../src/dart/include/internal/dart_api_dl_impl.h",
  ".../src/dart/include/dart_api.h",
  ".../src/dart/include/dart_native_api.h",
  ".../src/dart/include/dart_version.h"
]
```

This means modifying any zenoh-c header or Dart SDK header will trigger
recompilation. This is correct behavior for a from-source build strategy.

### 3. Build hooks still run twice (cosmetic)

Same behavior as A1 and A2 -- "Running build hooks..." printed twice.

## Prediction for B2 (CBuilder + @Native)

Based on the A1/A2 and A1/B1 results, B2 (CBuilder + @Native) should produce a
POSITIVE result. The @Native loading mechanism reads hook output metadata
regardless of whether the library was prebuilt or CBuilder-compiled. B2 should
combine CBuilder's automatic RUNPATH and source-level reproducibility with
@Native's correct asset resolution.
