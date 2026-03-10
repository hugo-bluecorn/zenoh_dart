# Native Library Bundling via Dart Build Hooks

> **Date**: 2026-03-09
> **Author**: CA (Architect)
> **Status**: Design complete, pending prototyping
> **Supersedes**: A->B->C progression from `prior-analysis.md`

## Decision

Use Dart build hooks (`hook/build.dart`) to compile the C shim and bundle
prebuilt `libzenohc.so` directly from the `packages/zenoh/` package. No
separate `zenoh_flutter` plugin package is needed.

This is Approach C from `prior-analysis.md`, which was originally
marked "long term." The landscape has changed: build hooks are now stable
(Dart 3.10+, Flutter 3.38+), `plugin_ffi` (`ffiPlugin: true`) is slated
for deprecation, and the canonical reference project (sqlite3) has already
completed its migration from `sqlite3_flutter_libs` to hooks.

## Background

### Why the Original Plan Changed

The March 7 analysis recommended A->B->C:
- **A** (pure Dart, manual .so placement) — now
- **B** (`zenoh_flutter` as `ffiPlugin: true` plugin) — medium term
- **C** (hooks/native_assets) — long term, when `native_toolchain_cmake` lands

As of March 9, three factors invalidate this progression:

1. **Build hooks are stable on our SDK** (Dart 3.11 / Flutter 3.41). They
   shipped as stable in Dart 3.10 (November 2025). We're one version ahead.
2. **`plugin_ffi` is deprecated-in-spirit**. Flutter 3.38+ generates
   `package_ffi` (with hooks) by default. Building a `ffiPlugin: true`
   plugin would be building on legacy infrastructure.
3. **sqlite3 completed the migration**. `sqlite3_flutter_libs` (the canonical
   FFI plugin pattern we planned to follow for Approach B) has been retired.
   sqlite3 v3.x uses `hook/build.dart` with prebuilt binaries downloaded
   from GitHub Releases.

### The Two-Library Problem (Unchanged)

zenoh-dart ships two native libraries:
- `libzenoh_dart.so` — C shim (compiled from `src/zenoh_dart.c`)
- `libzenohc.so` — zenoh-c runtime (compiled from Rust via Cargo)

`libzenoh_dart.so` has a `DT_NEEDED` entry for `libzenohc.so`. Both must
be bundled and findable at runtime.

This was the hardest part of any approach. It is now solved at the framework
level: Flutter PR #153054 ("Rewrite install names for relocated native
libraries") handles `install_name_tool` rewrites automatically when two
bundled libraries depend on each other. GitHub issue dart-lang/native#190
("Code Assets depending on other code assets") is **CLOSED as COMPLETED**.

## Architecture

### Package Structure (No zenoh_flutter)

```
packages/zenoh/
  pubspec.yaml                    # adds hooks, code_assets, native_toolchain_c
  hook/
    build.dart                    # NEW — compiles C shim + bundles libzenohc
  lib/
    zenoh.dart                    # existing public API (unchanged)
    src/
      native_lib.dart             # may need updates for @Native or asset loading
      bindings.dart               # auto-generated FFI bindings (unchanged)
  native/                         # NEW — prebuilt libzenohc.so per platform/ABI
    android/
      arm64-v8a/libzenohc.so
      x86_64/libzenohc.so
    linux/
      x86_64/libzenohc.so
      aarch64/libzenohc.so
src/                              # existing C shim source (monorepo root)
  zenoh_dart.h
  zenoh_dart.c
  dart/
    dart_api_dl.c
extern/
  zenoh-c/                        # v1.7.2 submodule (headers + developer build)
```

Key insight: **Flutter consumers just `flutter pub add zenoh`**. No separate
plugin package. The hooks handle native library compilation and bundling
transparently. CLI/Serverpod consumers continue using `dart run` — hooks
work identically for both runtimes.

### hook/build.dart Design

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // 1. Compile C shim from source
    final cBuilder = CBuilder.library(
      name: 'zenoh_dart',
      assetName: 'package:zenoh/src/native_lib.dart',
      sources: [
        'src/zenoh_dart.c',
        'src/dart/dart_api_dl.c',
      ],
      includes: [
        'extern/zenoh-c/include/',
      ],
      defines: {
        'DART_SHARED_LIB': null,
        'Z_FEATURE_SHARED_MEMORY': null,
        'Z_FEATURE_UNSTABLE_API': null,
      },
      libraries: ['zenohc'],
      libraryDirectories: [
        _resolveZenohcDir(input),
      ],
    );
    await cBuilder.run(input: input, output: output);

    // 2. Bundle prebuilt libzenohc.so for target platform
    final zenohcFile = _resolvePrebuiltZenohc(input);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'package:zenoh/src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: zenohcFile,
      ),
    );
  });
}

/// Resolve the directory containing libzenohc.so for linking.
///
/// During development: extern/zenoh-c/target/release/
/// For consumers: native/<os>/<arch>/
Uri _resolveZenohcDir(BuildInput input) {
  // Implementation depends on whether we're in dev mode or consumer mode
  // ...
}

/// Resolve the prebuilt libzenohc.so for the target platform.
///
/// Maps (targetOS, targetArchitecture) to the correct prebuilt binary:
///   android + arm64  -> native/android/arm64-v8a/libzenohc.so
///   android + x64    -> native/android/x86_64/libzenohc.so
///   linux + x64      -> native/linux/x86_64/libzenohc.so
///   linux + arm64    -> native/linux/aarch64/libzenohc.so
Uri _resolvePrebuiltZenohc(BuildInput input) {
  final os = input.config.code.targetOS;
  final arch = input.config.code.targetArchitecture;
  // ...
}
```

### pubspec.yaml Changes

```yaml
name: zenoh
description: "Dart bindings for the Zenoh pub/sub/query protocol via FFI."
version: 0.7.0  # major bump — hooks change the distribution model

resolution: workspace

environment:
  sdk: ^3.11.0

dependencies:
  args: ^2.6.0
  code_assets: ^1.0.0        # NEW — CodeAsset, DynamicLoadingBundled
  ffi: ^2.1.3
  hooks: ^1.0.0              # NEW — build() hook framework
  native_toolchain_c: any     # NEW — CBuilder for C compilation

dev_dependencies:
  ffigen: ^20.1.1
  lints: ^5.1.0
  test: ^1.25.0
```

**Important**: `hooks`, `code_assets`, and `native_toolchain_c` must be in
`dependencies`, NOT `dev_dependencies`. The Dart SDK runs hooks at build
time in the consumer's context, so these packages must be resolvable
transitively.

### native_lib.dart Changes

Two options for how Dart code loads the compiled libraries:

**Option 1: Keep DynamicLibrary.open() (minimal change)**

The build hook places `libzenoh_dart.so` in the correct platform-specific
location. `DynamicLibrary.open('libzenoh_dart.so')` continues to work
because the bundled library is in the app's library search path. No Dart
code changes needed.

**Option 2: Use @Native annotations (forward-looking)**

```dart
@DefaultAsset('package:zenoh/src/native_lib.dart')
library;

@Native<Int32 Function(Pointer<Void>)>()
external int zd_init_dart_api_dl(Pointer<Void> data);
```

This eliminates `DynamicLibrary.open()` entirely. Symbol resolution happens
automatically via the asset ID declared in the build hook. Requires
regenerating `bindings.dart` with ffigen configured for `@Native` output.

**Recommendation**: Start with Option 1 (minimal change). Migrate to Option 2
as a separate phase when convenient. The two-library bundling is the hard
part; the Dart loading mechanism is a cosmetic change.

## Prebuilt Binary Strategy

### Where Prebuilts Live

**Option A: Vendored in package (simpler, larger)**
- `native/android/arm64-v8a/libzenohc.so` (~5MB)
- `native/android/x86_64/libzenohc.so` (~5MB)
- `native/linux/x86_64/libzenohc.so` (~5MB)
- Total: ~15MB+ added to package
- Pro: no network dependency at build time
- Con: bloats pub.dev package, git repo

**Option B: Downloaded at build time (sqlite3's approach)**
- `hook/build.dart` downloads from GitHub Releases
- zenoh-c v1.7.2 has releases at `github.com/eclipse-zenoh/zenoh-c/releases`
- Pro: package stays small
- Con: network dependency at build time, needs hash verification

**Option C: Hybrid (recommended)**
- Android prebuilts vendored (no standard download source for Android ABIs)
- Linux prebuilts downloaded from zenoh-c GitHub Releases (available as ZIP)
- Developer mode falls back to `extern/zenoh-c/target/release/`

**Recommendation**: Start with Option A (vendored). The ~15MB is acceptable
for an initial release. Migrate to download-based later if package size
becomes a concern for pub.dev.

### Prebuilt Generation

Android prebuilts are already generated by `scripts/build_zenoh_android.sh`:
```bash
./scripts/build_zenoh_android.sh  # outputs to android/src/main/jniLibs/
```

Linux prebuilts come from the developer build:
```bash
cp extern/zenoh-c/target/release/libzenohc.so native/linux/x86_64/
```

Or downloaded from zenoh-c v1.7.2 GitHub Release:
```
https://github.com/eclipse-zenoh/zenoh-c/releases/tag/1.7.2
→ zenoh-c-1.7.2-x86_64-unknown-linux-gnu-standalone.zip
```

## Impact on Existing Consumers

### CLI / Serverpod (Approach A users)

`LD_LIBRARY_PATH` workflow continues to work unchanged. Build hooks also
run for `dart run`, so CLI consumers get automatic bundling too. This is
strictly an improvement — existing workflows don't break, but consumers
gain the option of hooks-based bundling.

### Tests

Tests currently use `LD_LIBRARY_PATH` to find native libraries:
```bash
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build fvm dart test
```

With hooks, `dart test` should find bundled libraries automatically. However,
this needs verification — the hook must produce assets during test builds.
If not, the `LD_LIBRARY_PATH` fallback remains valid.

### ffigen

No changes needed for Option 1 (keep `DynamicLibrary.open()`). ffigen
continues generating the same `ZenohDartBindings(DynamicLibrary)` constructor.

## Reference Projects

### sqlite3 (simolus3) — Canonical Reference

The closest precedent. Single C library compiled from source via `CBuilder`.
Prebuilt binaries downloaded from GitHub Releases. Migrated from
`sqlite3_flutter_libs` (legacy plugin) to `hook/build.dart` in v3.0.

**Difference from us**: Single library, no DT_NEEDED dependency. Simpler case.

### cbl-dart (Couchbase Lite) — Two-Library Reference

Two native libraries: `cblite` (prebuilt) + `cblitedart` (compiled glue code).
Same architecture as zenoh-dart. Gabriel Terwesten filed GitHub issue #190
about dependent code assets, which is now resolved.

**Difference from us**: Uses separate API packages per library. We bundle both
from a single package.

### dart-lang/native examples — Official Reference

`sqlite_prebuilt` example: `DynamicLoadingBundled()` with prebuilt binaries.
`native_add_library`: `CBuilder.library()` for compiling C source.
`native_dynamic_linking`: Multiple libraries with dependencies.

## Open Questions

### Q1: CBuilder + libraryDirectories for prebuilt dependency

Can `CBuilder.library()` link against `libzenohc.so` via `libraries: ['zenohc']`
and `libraryDirectories: ['/path/to/prebuilt/']` when `libzenohc.so` is also
declared as a separate `CodeAsset`? This should work (it's standard `-lzenohc
-L/path/` at the compiler level), but needs prototyping.

### Q2: zenoh-c header availability at consume time

`CBuilder` compiles `zenoh_dart.c`, which includes `zenoh.h` from
`extern/zenoh-c/include/`. For consumers who install via `pub add zenoh`,
`extern/zenoh-c/` won't exist (it's a git submodule, not published to pub.dev).

Options:
- **Vendor the headers** in `packages/zenoh/include/` (only ~200KB of headers)
- **Precompile the C shim too** and bundle both libraries as prebuilt
  (eliminates CBuilder entirely — both are `DynamicLoadingBundled`)
- **Download headers** at build time (fragile)

**Recommendation**: Precompile the C shim too. This eliminates the header
dependency entirely. Both `libzenoh_dart.so` and `libzenohc.so` become
prebuilt `CodeAsset` entries with `DynamicLoadingBundled()`. No `CBuilder`
needed. This is simpler and more reliable.

### Q3: Revised hook/build.dart (if both prebuilt)

If we precompile both libraries:

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final dir = _prebuiltDir(os, arch);

    // Library 1: prebuilt C shim
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:zenoh/src/native_lib.dart',
      linkMode: DynamicLoadingBundled(),
      file: dir.resolve('libzenoh_dart.so'),
    ));

    // Library 2: prebuilt zenoh-c runtime
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:zenoh/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: dir.resolve('libzenohc.so'),
    ));
  });
}

Uri _prebuiltDir(OS os, Architecture arch) {
  // Map to native/<os>/<arch>/
  // ...
}
```

This drops the `native_toolchain_c` dependency entirely. The hook is ~30
lines. Both libraries are precompiled for each platform/ABI and vendored
in the package.

**Trade-off**: Developers modifying the C shim still use CMake locally. The
hook only bundles prebuilts. This is fine — C shim development is rare after
a phase is complete.

### Q4: Platform library naming

Build hooks require consistent naming across architectures. Write output to
`input.outputDirectory` (unique per architecture) — do NOT add arch suffixes
to filenames. The framework handles the rest.

- Linux: `libzenoh_dart.so`, `libzenohc.so`
- Android: `libzenoh_dart.so`, `libzenohc.so`
- macOS: `libzenoh_dart.dylib`, `libzenohc.dylib`
- Windows: `zenoh_dart.dll`, `zenohc.dll`

### Q5: Impact on zenoh-counter-flutter

The counter Flutter app (`zenoh-counter-flutter`, separate repo) becomes a
simple Flutter app that depends on `package:zenoh` via path or pub.dev. No
native library handling needed in the app — the package's hooks handle
everything. This is a significant simplification.

## Research Findings (2026-03-10)

Research conducted against official Dart/Flutter documentation, dart-lang/native
and flutter/flutter GitHub issues, and real-world reference implementations
(sqlite3, cbl-dart). Full details in project memory
(`memory/hooks-experiment-design.md`).

### Critical Finding: DynamicLibrary.open() vs @Native

`DynamicLibrary.open('libfoo.so')` does **NOT** automatically find
hook-bundled assets. The hooks framework resolves assets via `@Native`
annotation asset IDs mapped to CodeAsset declarations. This means our
current `native_lib.dart` (which uses `DynamicLibrary.open()`) may not
work with hooks without modification.

This discovery adds a second independent variable to the experiment:
the library loading mechanism.

### Confirmed: Only Two Build Strategies Exist

- Link hooks (`hook/link.dart`) are for tree-shaking, not bundling
- `DynamicLoadingSystem()` is for system-installed libs, not bundled
- `StaticLinking` is **not yet supported** in Dart/Flutter SDK
- No third viable build strategy was found

### Linux RPATH

Must be set at **compile time** (`-Wl,-rpath,$ORIGIN`). CBuilder auto-adds
this. Post-hoc `patchelf` is unreliable per @blaugold (cbl-dart author).
Our CMake already sets `$ORIGIN` RPATH on `libzenoh_dart.so`.

### `native_toolchain_c` Is Experimental

pub.dev states: "higher expected rate of API and breaking changes." This
affects any approach using CBuilder.

### cbl-dart: Production-Proven Two-Library Precedent

Uses CBuilder + prebuilt (Approach B). Exact same architecture:
`libcblite.so` (prebuilt) + `libcblitedart.so` (CBuilder-compiled shim).
Linux soname handling requires copying prebuilt under both versioned and
unversioned names.

### `dart test` + Hooks

Hooks run automatically during `dart test` since Dart 3.10. However:
- Error reporting is poor (issue #1966, OPEN)
- Standalone Dart multi-library loading less mature than Flutter
- Must be verified empirically per approach

### Open Issues

| Issue | Impact | Status |
|-------|--------|--------|
| dart-lang/native#1966 | `dart test` error reporting buried | OPEN |
| dart-lang/native#2501 | macOS/Windows multi-lib broken | OPEN |
| dart-lang/sdk#53732 | Hook build stdout/stderr buried | OPEN |

## Implementation Plan: Scientific 2x2 Experiment

> **Supersedes** the original H1–H4 linear plan. The research revealed that
> two independent variables (build strategy + loading mechanism) require
> controlled experimentation before committing to a single approach.

### Experiment Design

**Question**: Which combination works best for zenoh-dart's two-library
bundling?

**Independent variables** (one per experiment):
1. Build strategy: both-prebuilt vs CBuilder+prebuilt
2. Loading mechanism: DynamicLibrary.open() vs @Native annotations

**2x2 Matrix**:

| | DynamicLibrary.open() | @Native annotations |
|---|---|---|
| **Both-prebuilt** | A1 (`exp_hooks_prebuilt_dlopen`) | A2 (`exp_hooks_prebuilt_native`) |
| **CBuilder + prebuilt** | B1 (`exp_hooks_cbuilder_dlopen`) | B2 (`exp_hooks_cbuilder_native`) |

### Package Structure

```
packages/
  zenoh/                         # control — UNTOUCHED
  exp_hooks_prebuilt_dlopen/         # A1: both-prebuilt + DynamicLibrary.open()
  exp_hooks_prebuilt_native/         # A2: both-prebuilt + @Native annotations
  exp_hooks_cbuilder_dlopen/         # B1: CBuilder + prebuilt + DynamicLibrary.open()
  exp_hooks_cbuilder_native/         # B2: CBuilder + prebuilt + @Native annotations
```

Each experiment package contains:
- `hook/build.dart` — the build hook under test
- `pubspec.yaml` — hooks dependencies (varies per approach)
- `lib/src/` — minimal Dart code to load and call one FFI function
- `test/` — minimal test exercising the FFI call
- `lessons-learned.md` — living document updated during experimentation

### Verification Criteria (6 tests per experiment)

1. Does the loading mechanism find bundled libs with `fvm dart run`?
2. Does the loading mechanism find bundled libs with `fvm dart test`?
3. Does `fvm flutter run` find bundled libs? (test Flutter app)
4. Does the DT_NEEDED dependency between the two libs resolve at runtime?
5. Does the hook build succeed on Linux x86_64?
6. Is error reporting adequate when something fails?

### Controlled Variables

- Same monorepo (zenoh-dart workspace)
- Same native libraries (libzenoh_dart.so + libzenohc.so from current build)
- Same Dart SDK (3.11.0 via fvm)
- Same Flutter SDK (3.41.4 via fvm)
- Same zenoh-c version (v1.7.2)
- Same FFI function called (e.g., `zd_init_dart_api_dl`)

### Decision Criteria (for final analysis)

- **Correctness**: Does it work on Linux x86_64?
- **Simplicity**: Lines of hook code, number of dependencies
- **Stability**: Experimental vs stable dependencies
- **Developer experience**: Can C shim developers iterate without friction?
- **Consumer experience**: Does `dart pub add zenoh` + `dart run` just work?
- **Test compatibility**: Does `dart test` find bundled libs?
- **pub.dev viability**: Can the package be published with this approach?
- **Maintainability**: How much changes when zenoh-c upgrades?

### Execution Order

Experiments should be implemented in order A1 → A2 → B1 → B2 (simplest
first). Each experiment's `lessons-learned.md` informs the next. After all
four are complete, a comparative analysis determines the winner. The winning
approach is then applied to `packages/zenoh/`.

## References

- [Dart Hooks documentation](https://dart.dev/tools/hooks)
- [Flutter: Bind to native code using FFI](https://docs.flutter.dev/platform-integration/bind-native-code)
- [CBuilder class API](https://pub.dev/documentation/native_toolchain_c/latest/native_toolchain_c/CBuilder-class.html)
- [CodeAsset class API](https://pub.dev/documentation/code_assets/latest/code_assets/CodeAsset-class.html)
- [dart-lang/native#190: Code Assets depending on other code assets](https://github.com/dart-lang/native/issues/190) — CLOSED COMPLETED
- [dart-lang/native#1966: Native assets don't resolve in unit tests](https://github.com/dart-lang/native/issues/1966) — OPEN
- [dart-lang/native#2501: native_dynamic_linking access violation](https://github.com/dart-lang/native/issues/2501) — OPEN
- [dart-lang/sdk#53732: Should surface stdout/stderr from build.dart](https://github.com/dart-lang/sdk/issues/53732) — OPEN
- [Flutter PR #153054: Rewrite install names for relocated native libraries](https://github.com/flutter/flutter/pull/153054) — MERGED
- [dart-lang/native hooks examples](https://github.com/dart-lang/native/blob/main/pkgs/hooks/example/README.md)
- [native_dynamic_linking example](https://github.com/dart-lang/native/tree/main/pkgs/hooks/example/build/native_dynamic_linking)
- [sqlite_prebuilt example](https://github.com/dart-lang/native/tree/main/pkgs/code_assets/example/sqlite_prebuilt)
- [sqlite3 package](https://pub.dev/packages/sqlite3) — canonical hooks migration (simolus3/sqlite3.dart)
- [cbl_dart package](https://pub.dev/packages/cbl_dart) — two-library precedent (cbl-dart/cbl-dart)
- [Simon Binder: Using native assets in existing FFI packages](https://www.simonbinder.eu/posts/native_assets/)
- [prior-analysis.md](prior-analysis.md) — original A/B/C analysis (superseded)
