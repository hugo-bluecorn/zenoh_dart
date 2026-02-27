# Phase P1: Packaging & Build Infrastructure (Pure Dart)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. This is a Melos monorepo with the Dart package at `packages/zenoh/`
and C shim source at the monorepo root under `src/`.

See `docs/phases/phase-00-bootstrap.md` for full architecture.

### Architecture (abbreviated)

```
Dart CLI example (packages/zenoh/bin/z_*.dart)
  → Idiomatic Dart API (packages/zenoh/lib/src/*.dart)
  → Generated FFI bindings (packages/zenoh/lib/src/bindings.dart)
  → C shim (src/zenoh_dart.h/.c)
  → libzenohc.so (zenoh-c v1.7.2)
```

### Why this phase exists

After Phase 0, the package can only be built from a local checkout with
`extern/zenoh-c` built in-tree. Blockers preventing general use:

1. `src/CMakeLists.txt` has a hardcoded path to `extern/zenoh-c/target/release`
2. No prebuilt `libzenohc.so` is available for Linux
3. No Android cross-compiled `libzenohc.so` exists
4. Test infrastructure needs `LD_LIBRARY_PATH` setup

This phase fixes build infrastructure so the package can be developed and
tested reliably on Linux, and provides Android cross-compilation tooling.

### What changed from the original spec

This spec was originally written for a Flutter FFI plugin. The following parts
are **deferred to Phase PF** (the future `zenoh_flutter` package):

- `linux/CMakeLists.txt` `bundled_libraries` — Flutter plugin concept
- `android/build.gradle` + jniLibs — Flutter plugin concept
- `flutter build apk/linux` verification — this is a pure Dart package
- Flutter end-to-end consumer test

Phase P1 for `zenoh` focuses on: standalone CMake build, 3-tier library
discovery, prebuilt Linux `libzenohc.so`, Android build script (reference),
and Dart test infrastructure.

## Prior Phases

### Phase 0 (Bootstrap) — completed

- C shim: session/config/keyexpr/bytes management (Dart native API DL init,
  logging, 20+ functions)
- Dart: `Config`, `Session`, `KeyExpr`, `ZBytes`, `ZenohException`
- Build: CMakeLists links libzenohc, ffigen generates bindings to `lib/src/bindings.dart`
- Files: `packages/zenoh/lib/src/{bindings,native_lib,exceptions,config,session,keyexpr,bytes}.dart`

## This Phase's Goal

Establish robust build infrastructure for the pure Dart `zenoh` package:

1. Fix `src/CMakeLists.txt` with 3-tier `libzenohc.so` discovery
2. Provide prebuilt `libzenohc.so` for Linux x86_64
3. Create Android cross-compilation script via cargo-ndk
4. Simplify `native_lib.dart` to single-load (OS linker resolves zenohc)
5. Ensure `fvm dart test` works reliably with `LD_LIBRARY_PATH`

### What this phase does NOT do

- Flutter plugin packaging (deferred to Phase PF / `zenoh_flutter`)
- Publish to pub.dev (future work)
- Support iOS, macOS, or Windows (future phases)
- Use hook/build.dart / native assets (deferred to Phase P2)
- Add CI/CD for prebuilt generation (future work)
- Change any Dart API surface (no new classes, methods, or behaviors)

## Design Decisions

### Single-load Dart library loading

**Current state:** `native_lib.dart` may explicitly load TWO libraries.

**Change:** Load only `libzenoh_dart.so`. The OS dynamic linker resolves
`libzenohc.so` as a transitive dependency because:
- On Linux: `libzenoh_dart.so` has `DT_NEEDED` for `libzenohc.so`, and
  RPATH is set to `$ORIGIN` so the linker finds it in the same directory
- On Android: Both `.so` files are in the APK's `lib/{ABI}/` directory

### Platform-aware zenohc discovery in CMake

`src/CMakeLists.txt` must find `libzenohc.so` from three possible locations,
checked in order:

1. **Android jniLibs** — `android/src/main/jniLibs/${ANDROID_ABI}/libzenohc.so`
   (future Flutter plugin, or after running build script)
2. **Prebuilt native directory** — `native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so`
   (prebuilt for Linux desktop)
3. **Developer fallback** — `extern/zenoh-c/target/release/libzenohc.so`
   (local dev build from submodule)

### Linux prebuilt strategy

- Extract `libzenohc.so` from the official zenoh-c v1.7.2 GitHub release
  standalone ZIP for `x86_64-unknown-linux-gnu`
- Place at `native/linux/x86_64/libzenohc.so`
- Git-tracked for now

### Android prebuilt strategy

- Use `cargo-ndk` (v4.1.2, available at `extern/cargo-ndk`) to cross-compile
- Target ABIs: **arm64-v8a** (real devices) + **x86_64** (emulator)
- Output to `android/src/main/jniLibs/{ABI}/libzenohc.so`
- Build script: `scripts/build_zenoh_android.sh`
- Android prebuilts are NOT git-tracked in the pure Dart package (they belong
  in the future `zenoh_flutter` package)

### Test infrastructure

Tests use `LD_LIBRARY_PATH` to find native libraries:

```bash
cd packages/zenoh && LD_LIBRARY_PATH=../../native/linux/x86_64:../../extern/zenoh-c/target/release fvm dart test
```

## File Changes

### Modified files

#### `src/CMakeLists.txt` — Platform-aware zenohc discovery

Replace the current minimal build with 3-tier discovery:

```cmake
# ----------- zenoh-c library discovery -----------
get_filename_component(PACKAGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)

if(ANDROID)
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/android/src/main/jniLibs/${ANDROID_ABI}")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
elseif(EXISTS "${PACKAGE_ROOT}/native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so")
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/native/linux/${CMAKE_SYSTEM_PROCESSOR}")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
else()
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/extern/zenoh-c/target/release")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
endif()

if(NOT EXISTS "${ZENOHC_LIBRARY}")
  message(FATAL_ERROR "zenoh-c library not found at: ${ZENOHC_LIBRARY}")
endif()

add_library(zenohc SHARED IMPORTED)
set_target_properties(zenohc PROPERTIES
  IMPORTED_LOCATION "${ZENOHC_LIBRARY}"
  IMPORTED_NO_SONAME TRUE
)

target_link_libraries(zenoh_dart PRIVATE zenohc)

if(NOT ANDROID)
  set_target_properties(zenoh_dart PROPERTIES
    BUILD_RPATH "${ZENOHC_LIB_DIR}"
    INSTALL_RPATH "$ORIGIN"
  )
endif()
```

#### `packages/zenoh/lib/src/native_lib.dart` — Single-load simplification

Remove any explicit zenohc loading. Only load `libzenoh_dart.so`.

### New files

#### `native/linux/x86_64/libzenohc.so` — Linux prebuilt

Extracted from the official zenoh-c v1.7.2 release ZIP.

#### `scripts/build_zenoh_android.sh` — Android cross-compilation script

Builds `libzenohc.so` for Android ABIs using cargo-ndk.

### Files NOT changed

- `packages/zenoh/ffigen.yaml` — No changes
- `packages/zenoh/pubspec.yaml` — No changes
- All Dart API files except `native_lib.dart` — No API surface changes
- `src/zenoh_dart.h`, `src/zenoh_dart.c` — No C shim changes

## zenoh-c APIs Wrapped

No new zenoh-c APIs wrapped in this phase. This is a build infrastructure phase.

## Verification

### Build verification

1. **Linux dev build**: `extern/zenoh-c` built locally →
   `src/CMakeLists.txt` finds zenohc at `extern/zenoh-c/target/release/` →
   C shim compiles and links → `fvm dart test` passes
2. **Linux prebuilt build**: zenohc found at `native/linux/x86_64/` →
   same result
3. **Android build**: `scripts/build_zenoh_android.sh` produces
   `android/src/main/jniLibs/{arm64-v8a,x86_64}/libzenohc.so`
4. **ffigen**: `fvm dart run ffigen --config ffigen.yaml` generates
   `lib/src/bindings.dart` without errors
5. **dart analyze**: `fvm dart analyze packages/zenoh` — no errors

### Runtime verification

6. **Existing tests pass**: `fvm dart test` with `LD_LIBRARY_PATH` pointing
   to the library location — all session, keyexpr, bytes tests green
7. **Single-load works**: After `native_lib.dart` change, verify that
   bindings load successfully (zenohc resolved by OS linker, not explicit
   Dart load)

## Commands Reference

All commands use `fvm` (Dart and Flutter are not on PATH):

```bash
# Build zenoh-c (developer)
RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release

# Build for Android
./scripts/build_zenoh_android.sh

# Run tests
cd packages/zenoh && LD_LIBRARY_PATH=../../native/linux/x86_64 fvm dart test

# Analyze
fvm dart analyze packages/zenoh

# Regenerate bindings
cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml
```
