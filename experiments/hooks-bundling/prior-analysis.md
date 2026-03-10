# zenoh_flutter Package Analysis

> **Date**: 2026-03-07
> **Author**: CA (Architect)
> **Status**: Analysis complete, decision pending

## Question

Should the zenoh-dart monorepo create a separate `zenoh_flutter` package
(Flutter plugin) in `packages/zenoh_flutter/`, or is the pure Dart `zenoh`
package sufficient for Flutter applications?

## Background

The zenoh-dart monorepo was originally structured to support multiple packages
(`packages/*` workspace glob in Melos). The provisional thinking was:
- `packages/zenoh/` — pure Dart FFI package (CLI, Serverpod, any Dart runtime)
- `packages/zenoh_flutter/` — Flutter plugin wrapping `package:zenoh` with
  platform-specific native library bundling

As of 2026-03-07, only `packages/zenoh/` exists. This analysis evaluates
whether `zenoh_flutter` is needed, given the current state of Dart 3.11 /
Flutter 3.41 and the native_assets feature.

## Current Native Library Loading

**File**: `packages/zenoh/lib/src/native_lib.dart`

The package uses `DynamicLibrary.open()` with bare library names:
- Linux/Android: `libzenoh_dart.so`
- macOS/iOS: `libzenoh_dart.dylib`
- Windows: `zenoh_dart.dll`

This relies on the OS dynamic linker to find the library. Additionally,
`libzenoh_dart.so` has a `DT_NEEDED` dependency on `libzenohc.so`, so
**both libraries** must be findable at runtime.

The generated bindings (`bindings.dart`) use the old-style
`ZenohDartBindings(ffi.DynamicLibrary)` constructor, not `@Native` annotations.

## Three Approaches Evaluated

### Approach A: Pure Dart Package Only (Current State)

The `zenoh` package stays as-is. Flutter consumers handle native library
placement themselves.

**How it works per platform:**

| Platform | Consumer must... |
|----------|-----------------|
| CLI / Serverpod | Set `LD_LIBRARY_PATH` |
| Flutter Android | Copy .so files to `android/app/src/main/jniLibs/<abi>/` |
| Flutter Linux | Modify runner `CMakeLists.txt` to bundle .so files |

**Strengths:**
- Simplest package structure — no Flutter dependency in zenoh package
- Works for all Dart runtimes (CLI, Serverpod, Flutter, etc.)
- Single package to maintain
- No prebuilt binary distribution concerns at the package level

**Weaknesses:**
- Every Flutter consumer must manually handle native library placement
- No `flutter test` support (libraries not discoverable)
- Poor developer experience — not a "just add to pubspec" package
- Error-prone — easy to miss an ABI or forget libzenohc.so

### Approach B: Pure Dart + zenoh_flutter Plugin Wrapper

Add `packages/zenoh_flutter/` as a thin Flutter plugin that bundles the
native libraries and re-exports the Dart API.

**What zenoh_flutter would contain:**

```
packages/zenoh_flutter/
  pubspec.yaml               # flutter plugin: { ffiPlugin: true }
  lib/zenoh_flutter.dart     # export 'package:zenoh/zenoh.dart';
  android/
    build.gradle
    src/main/
      CMakeLists.txt          # builds libzenoh_dart.so, bundles libzenohc.so
      jniLibs/<abi>/          # prebuilt libzenohc.so per ABI
  linux/
    CMakeLists.txt            # builds libzenoh_dart.so, sets bundled_libraries
```

Zero Dart code duplication. The plugin is purely build/bundle infrastructure.

**How it works:**
- Flutter's build system auto-invokes the plugin's per-platform CMakeLists.txt
- Android: Gradle picks up CMakeLists.txt via `externalNativeBuild`, compiles
  C shim, bundles both .so files into APK
- Linux: Flutter CMake invokes plugin CMake, bundles via
  `${PLUGIN}_bundled_libraries`
- Dart CLI consumers continue using `package:zenoh` directly

**Strengths:**
- "Just add to pubspec" for Flutter developers
- Automatic native library build and bundling per platform
- Proven pattern (sqlite3_flutter_libs did this for years)
- Monorepo already structured for this split
- Clear separation: `zenoh` = API, `zenoh_flutter` = distribution

**Weaknesses:**
- Two packages to maintain (though zenoh_flutter is thin — mostly CMake)
- Flutter officially calls plugin_ffi "legacy" as of Flutter 3.38+
- Must ship prebuilt `libzenohc.so` binaries per platform/ABI
- Per-platform CMakeLists.txt maintenance

### Approach C: Native Assets via hook/build.dart

Use Dart's native_assets feature (stable since Dart 3.10 / Flutter 3.38) to
bundle native libraries from the pure Dart package itself — no separate
Flutter plugin needed.

**What this adds to packages/zenoh/:**

```
packages/zenoh/
  hook/build.dart            # Dart build hook
  pubspec.yaml               # adds: hooks, code_assets, native_toolchain_c
```

**How it works:**
- `hook/build.dart` runs at build time (both `dart run` and `flutter run`)
- The hook compiles the C shim and declares `CodeAsset` entries for both
  `libzenoh_dart.so` and `libzenohc.so`
- With `@Native` annotations, symbol resolution is automatic (no
  `DynamicLibrary.open()` needed)
- Works identically for Dart CLI, Flutter Android, Flutter Linux, etc.

**Strengths:**
- Single package for Dart and Flutter — the official recommendation
- No separate plugin package
- Automatic bundling across all platforms
- `flutter test` support
- Forward-looking, actively maintained by Dart/Flutter team

**Weaknesses (significant for zenoh-dart):**
- No `native_toolchain_cmake` exists (dart-lang/native#2036 is a proposal)
- `native_toolchain_c` can compile simple C but can't drive CMake builds
- C shim depends on zenoh-c headers — hook must vendor or download them
- `libzenohc.so` is built from Rust via Cargo — no toolchain can invoke Cargo
  at consume time; must always be prebuilt
- Two `CodeAsset` declarations needed (or transitive loading)
- Would require ffigen regeneration for `@Native` annotations
- Significantly more complex than sqlite3's migration (single .c file, no
  external dependencies)

## The Two-Library Problem

This is unique to zenoh-dart and the critical differentiator in this analysis.

Most FFI packages ship a single native library. zenoh-dart ships **two**:
- `libzenoh_dart.so` — C shim (compiled from `src/zenoh_dart.c`)
- `libzenohc.so` — zenoh-c runtime (compiled from Rust via Cargo)

`libzenoh_dart.so` has a `DT_NEEDED` entry for `libzenohc.so`, meaning the
OS dynamic linker must find both at runtime. This is a transitive native
dependency — uncommon in the Dart/Flutter ecosystem.

Additionally, `libzenohc.so` cannot be compiled at consume time because it
requires the Rust toolchain and Cargo. It must always be distributed as a
prebuilt binary.

This complicates every approach:
- **A**: Consumer must place both libraries
- **B**: Plugin CMake builds one, bundles the other
- **C**: Hook must handle both (compile one, download/bundle the other)

## Recommendation

### Progression: A -> B -> C

| Timeframe | Approach | Trigger |
|-----------|----------|---------|
| **Now** (counter MVP) | A | Internal app, manual .so placement is documented |
| **Medium term** | B | External Flutter consumers, pub.dev publication |
| **Long term** | C | When `native_toolchain_cmake` lands and stabilizes |

### Rationale

**Now**: The counter app is an internal template project. Manually placing
.so files in jniLibs and documenting the steps in `lessons-learned.md` is
itself valuable — future projects need this recipe. Approach A has zero
additional package maintenance.

**Medium term**: When we want external developers to `flutter pub add
zenoh_flutter` and have it just work, Approach B is the pragmatic choice.
The monorepo is ready for it, the pattern is proven, and the zenoh_flutter
package is thin (mostly CMake). The existing `src/CMakeLists.txt` three-tier
discovery already handles the hard parts.

**Long term**: Monitor dart-lang/native#2036 (`native_toolchain_cmake`) and
the evolution of `code_assets`. When CMake-based hooks are stable and widely
adopted, migrate from B to C and deprecate zenoh_flutter.

### Key Insight

There is **no API reason** for zenoh_flutter to exist. It would contain zero
Dart logic — just CMake files and a one-line re-export. The question is purely
about native library distribution mechanics.

## References

- [Dart Hooks Documentation](https://dart.dev/tools/hooks)
- [Flutter: Bind to native code using FFI](https://docs.flutter.dev/platform-integration/bind-native-code)
- [Flutter: Android C interop](https://docs.flutter.dev/platform-integration/android/c-interop)
- [Simon Binder: Using native assets in existing FFI packages](https://www.simonbinder.eu/posts/native_assets/)
- [dart-lang/native#2036: native_toolchain_cmake proposal](https://github.com/dart-lang/native/issues/2036)
- [Flutter#181694: FFI package with cmake dependencies](https://github.com/flutter/flutter/issues/181694)
- [sqlite3 package (migrated to hooks)](https://pub.dev/packages/sqlite3)
- [sqlite3_flutter_libs (now deprecated)](https://pub.dev/packages/sqlite3_flutter_libs)
