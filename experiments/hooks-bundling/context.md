# Hooks Bundling Experiment — Project Context

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Purpose**: Self-contained context document for the Dart build hooks
> experiment. Readable by humans and usable as cold-start context for any
> Claude session that lacks project memory.

## What This Experiment Is About

The zenoh-dart package ships **two native shared libraries** that must be
bundled together:

- `libzenoh_dart.so` — a thin C shim wrapping zenoh-c macros and inline
  functions that Dart FFI cannot call directly
- `libzenohc.so` — the zenoh-c runtime (compiled from Rust via Cargo)

`libzenoh_dart.so` has a `DT_NEEDED` entry for `libzenohc.so`. Both must
be loadable at runtime. Today, developers set `LD_LIBRARY_PATH` manually.
This experiment determines the best way to use **Dart build hooks**
(`hook/build.dart`, stable since Dart 3.10) to bundle both libraries
automatically — eliminating `LD_LIBRARY_PATH` for consumers and enabling
`flutter pub add zenoh` to just work.

## Project Context

### zenoh-dart Monorepo

- **Repository**: `hugo-bluecorn/zenoh-dart` (GitHub)
- **Location**: `/home/hugo-bluecorn/bluecorn/CSR/git/zenoh_dart/`
- **Structure**: Melos monorepo. Main package at `packages/zenoh/`.
  C shim source at `src/zenoh_dart.{h,c}`. zenoh-c v1.7.2 submodule at
  `extern/zenoh-c/`.
- **SDK**: Dart 3.11.0 / Flutter 3.41.4 via FVM. Bare `dart`/`flutter`
  are NOT on PATH — all commands must use `fvm dart`, `fvm flutter`.
- **Status**: Phases 0–5 complete. 62 C shim functions, 185 integration
  tests, 18 Dart API classes, 7 CLI examples. Phase 6 (Get/Queryable)
  not yet started.

### Three-Layer Architecture

```
Dart API (packages/zenoh/lib/src/*.dart)
  ↓ dart:ffi
Generated FFI bindings (packages/zenoh/lib/src/bindings.dart)
  ↓ DynamicLibrary.open('libzenoh_dart.so')
C shim (src/zenoh_dart.c) → libzenoh_dart.so
  ↓ DT_NEEDED
zenoh-c runtime → libzenohc.so
```

The current loading mechanism in `packages/zenoh/lib/src/native_lib.dart`
uses `DynamicLibrary.open('libzenoh_dart.so')`. The OS dynamic linker
then resolves `libzenohc.so` via the DT_NEEDED entry.

### Current Build Flow (Pre-Hooks)

```bash
# Build zenoh-c (Rust → libzenohc.so)
RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release

# Build C shim (C → libzenoh_dart.so, links against libzenohc.so)
cmake --build build

# Run tests (must set LD_LIBRARY_PATH manually)
cd packages/zenoh && \
  LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart test
```

### Development Workflow

This project uses a four-session role pattern:

| Session | Role | Scope |
|---------|------|-------|
| **CA** | Architect / Reviewer | Decisions, design docs, memory |
| **CP** | Planner | TDD slice decomposition via `/tdd-plan` |
| **CI** | Implementer | Code, tests, releases via `/tdd-implement` |
| **CB** | Packaging Advisor | Build, distribution, pub.dev |

CA produces design docs → CP produces TDD plans → CI implements.

## Why Build Hooks

### Original Plan (Superseded)

The March 7 analysis (`prior-analysis.md`) recommended a three-step
progression:

- **A** (pure Dart, manual .so placement) — current state
- **B** (`zenoh_flutter` as `ffiPlugin: true` plugin) — medium term
- **C** (hooks/native_assets) — long term

### Why We Skipped to C

Three factors invalidated the A→B→C progression (as of March 9):

1. **Build hooks are stable** on our SDK (Dart 3.11 / Flutter 3.41).
   Shipped stable in Dart 3.10 (November 2025).
2. **`plugin_ffi` is deprecated-in-spirit**. Flutter 3.38+ generates
   `package_ffi` (with hooks) by default for new FFI projects.
3. **sqlite3 completed the migration**. The canonical FFI plugin pattern
   we planned to follow (`sqlite3_flutter_libs`) has been retired. sqlite3
   v3.x uses `hook/build.dart` with prebuilt binaries.

### The Two-Library Problem (Solved at Framework Level)

The hardest part of any approach was ensuring both libraries are co-located
at runtime. This is now solved:

- **dart-lang/native#190** ("Code Assets depending on other code assets")
  — CLOSED COMPLETED (December 2024)
- **Flutter PR #153054** ("Rewrite install names for relocated native
  libraries") — MERGED (August 2024). Handles macOS/iOS `install_name_tool`
  rewrites when two bundled libraries depend on each other.
- **Linux**: All `DynamicLoadingBundled` assets land in one flat directory.
  Libraries compiled with `-rpath=$ORIGIN` find each other. Our CMake
  already sets this.

## Research Findings (2026-03-10)

Four parallel research agents investigated official Dart/Flutter docs,
dart-lang/native issues, flutter/flutter issues, and real-world
implementations (sqlite3, cbl-dart).

### Only Two Build Strategies Exist

- **Both-prebuilt**: Both `.so` files are precompiled. Hook declares two
  `CodeAsset` entries with `DynamicLoadingBundled()`. No compilation at
  build time. Dependencies: `hooks`, `code_assets` only.
- **CBuilder + prebuilt**: `CBuilder.library()` compiles the C shim from
  source at build time, linking against prebuilt `libzenohc.so`. The
  prebuilt is also declared as a `CodeAsset`. Dependencies: `hooks`,
  `code_assets`, `native_toolchain_c`.

Other options were ruled out:
- Link hooks (`hook/link.dart`) — for tree-shaking, not bundling
- `DynamicLoadingSystem()` — for system-installed libs, not bundled
- `StaticLinking` — **not yet supported** in Dart/Flutter SDK

### Critical Finding: Library Loading Mechanism

**`DynamicLibrary.open('libfoo.so')` does NOT automatically find
hook-bundled assets.** The hooks framework resolves assets via `@Native`
annotation asset IDs mapped to `CodeAsset` declarations in the build hook.

This means our current `native_lib.dart` (which uses
`DynamicLibrary.open()`) may not work with hooks without modification.
The `@Native` annotation approach eliminates `DynamicLibrary.open()`
entirely — symbol resolution happens automatically via asset ID matching.

This discovery created a **second independent variable** for the experiment.

### Platform-Specific RPATH

| Platform | Inter-library resolution | Handler |
|----------|------------------------|---------|
| Linux | `$ORIGIN` RPATH, both libs in same dir | Must be set at compile time. CBuilder auto-adds. Post-hoc patchelf unreliable. |
| macOS/iOS | `install_name_tool` rewriting | Flutter PR #153054 (merged, in 3.41.x) |
| Android | APK `lib/<abi>/` auto-searched | Framework handles it |
| Windows | Buggy | Open issue dart-lang/native#2501 |

### `dart test` + Hooks

- Hooks run automatically during `dart test` since Dart 3.10
- Error reporting is poor — hook failures show only "Couldn't resolve
  native function" (dart-lang/native#1966, OPEN)
- Standalone Dart multi-library loading is less mature than Flutter
- Must be verified empirically per approach

### `native_toolchain_c` Is Experimental

pub.dev states: "higher expected rate of API and breaking changes." This
affects any approach using CBuilder (experiments B1, B2).

### Real-World References

| Project | Architecture | Approach |
|---------|-------------|----------|
| **cbl-dart** (Couchbase Lite) | `libcblite.so` (prebuilt) + `libcblitedart.so` (CBuilder shim) | CBuilder + prebuilt. Exact same architecture as zenoh-dart. Production-proven. |
| **sqlite3** (simolus3) | Single `libsqlite3.so` | Three modes: prebuilt download, CBuilder compile, system. Canonical hooks reference. |
| **native_dynamic_linking** (dart-lang) | Three libs with dependency chain | All CBuilder, sequential. Official example. Linux works, macOS/Windows buggy. |

### Open Issues

| Issue | Impact | Status |
|-------|--------|--------|
| dart-lang/native#1966 | `dart test` error reporting buried | OPEN |
| dart-lang/native#2501 | macOS/Windows multi-lib broken | OPEN |
| dart-lang/sdk#53732 | Hook stdout/stderr buried | OPEN |

## Experiment Design

### Scientific Method

**Question**: Which combination of build strategy and loading mechanism
works best for zenoh-dart's two-library bundling?

**Controlled variables**: Same monorepo, same native libs, same zenoh-c
v1.7.2, same Dart 3.11.0 / Flutter 3.41.4.

**Independent variables** (one changed per experiment):
1. Build strategy: both-prebuilt vs CBuilder+prebuilt
2. Loading mechanism: `DynamicLibrary.open()` vs `@Native` annotations

### 2x2 Matrix

| | DynamicLibrary.open() | @Native annotations |
|---|---|---|
| **Both-prebuilt** | A1 (`exp_hooks_prebuilt_dlopen`) | A2 (`exp_hooks_prebuilt_native`) |
| **CBuilder + prebuilt** | B1 (`exp_hooks_cbuilder_dlopen`) | B2 (`exp_hooks_cbuilder_native`) |

### Package Structure

```
packages/
  zenoh/                         # control — UNTOUCHED
  exp_hooks_prebuilt_dlopen/         # A1
  exp_hooks_prebuilt_native/         # A2
  exp_hooks_cbuilder_dlopen/         # B1
  exp_hooks_cbuilder_native/         # B2
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

### Execution Order

A1 → A2 → B1 → B2 (simplest first). Each experiment's
`lessons-learned.md` informs the next.

### Decision Criteria

After all four experiments complete, compare on:

- **Correctness**: Does it work on Linux x86_64?
- **Simplicity**: Lines of hook code, number of dependencies
- **Stability**: Experimental vs stable dependencies
- **Developer experience**: Can C shim developers iterate?
- **Consumer experience**: Does `dart pub add zenoh` + `dart run` just work?
- **Test compatibility**: Does `dart test` find bundled libs?
- **pub.dev viability**: Can the package be published?
- **Maintainability**: Upgrade friction when zenoh-c changes version?

The winning approach is then applied to `packages/zenoh/`.

## Key API Reference (for implementers)

### Build hook skeleton (both-prebuilt)

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final dir = _prebuiltDir(os, arch);

    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:zenoh/src/native_lib.dart',
      linkMode: DynamicLoadingBundled(),
      file: dir.resolve(os.dylibFileName('zenoh_dart')),
    ));

    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:zenoh/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: dir.resolve(os.dylibFileName('zenohc')),
    ));
  });
}
```

### Build hook skeleton (CBuilder + prebuilt)

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // 1. Bundle prebuilt libzenohc.so
    final zenohcFile = _resolvePrebuiltZenohc(input);
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'package:zenoh/src/zenohc.dart',
      linkMode: DynamicLoadingBundled(),
      file: zenohcFile,
    ));

    // 2. Compile C shim, linking against prebuilt zenohc
    final cBuilder = CBuilder.library(
      name: 'zenoh_dart',
      assetName: 'package:zenoh/src/native_lib.dart',
      sources: ['src/zenoh_dart.c', 'src/dart/dart_api_dl.c'],
      includes: ['include/'],  // vendored zenoh-c headers
      libraries: ['zenohc'],
      libraryDirectories: [_zenohcDir(input)],
    );
    await cBuilder.run(input: input, output: output);
  });
}
```

### pubspec.yaml dependencies

```yaml
# A1/A2 (both-prebuilt) — stable deps only
dependencies:
  hooks: ^1.0.0
  code_assets: ^1.0.0

# B1/B2 (CBuilder) — includes experimental dep
dependencies:
  hooks: ^1.0.0
  code_assets: ^1.0.0
  native_toolchain_c: ^0.17.5  # EXPERIMENTAL
```

### @Native annotation pattern

```dart
@DefaultAsset('package:zenoh/src/native_lib.dart')
library;

import 'dart:ffi';

@Native<Int32 Function(Pointer<Void>)>()
external int zd_init_dart_api_dl(Pointer<Void> data);
```

Asset ID `package:zenoh/src/native_lib.dart` must match the `name` field
in the CodeAsset declaration in `hook/build.dart`.

## Reference Links

- [Dart hooks documentation](https://dart.dev/tools/hooks)
- [Flutter FFI guide](https://docs.flutter.dev/platform-integration/bind-native-code)
- [hooks ^1.0.2 on pub.dev](https://pub.dev/packages/hooks)
- [code_assets ^1.0.0 on pub.dev](https://pub.dev/packages/code_assets)
- [native_toolchain_c ^0.17.5 on pub.dev](https://pub.dev/packages/native_toolchain_c)
- [dart-lang/native#190](https://github.com/dart-lang/native/issues/190) — Code Assets depending on other code assets (CLOSED)
- [dart-lang/native#1966](https://github.com/dart-lang/native/issues/1966) — Native assets don't resolve in unit tests (OPEN)
- [dart-lang/native#2501](https://github.com/dart-lang/native/issues/2501) — native_dynamic_linking access violation (OPEN)
- [Flutter PR #153054](https://github.com/flutter/flutter/pull/153054) — install_name rewriting (MERGED)
- [native_dynamic_linking example](https://github.com/dart-lang/native/tree/main/pkgs/hooks/example/build/native_dynamic_linking)
- [sqlite_prebuilt example](https://github.com/dart-lang/native/tree/main/pkgs/code_assets/example/sqlite_prebuilt)
- [sqlite3 package](https://pub.dev/packages/sqlite3) — canonical hooks migration
- [cbl-dart](https://github.com/cbl-dart/cbl-dart) — two-library production reference
- [Simon Binder: Using native assets in existing FFI packages](https://www.simonbinder.eu/posts/native_assets/)

## File Index

```
experiments/hooks-bundling/
  context.md          # this file — self-contained project context
  design.md           # primary design doc + experiment plan + research
  prior-analysis.md   # original A/B/C analysis (superseded, provenance)
```

Per-experiment living documents (created during implementation):
```
packages/exp_hooks_prebuilt_dlopen/lessons-learned.md   # A1
packages/exp_hooks_prebuilt_native/lessons-learned.md   # A2
packages/exp_hooks_cbuilder_dlopen/lessons-learned.md   # B1
packages/exp_hooks_cbuilder_native/lessons-learned.md   # B2
```
