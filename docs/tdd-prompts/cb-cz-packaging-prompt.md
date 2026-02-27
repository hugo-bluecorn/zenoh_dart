# CZ Session Prompt: Phase P1 — Packaging & Distribution (Linux + Android)

Paste this prompt at the start of the CZ Claude Code session, then run
`/tdd-plan` with it.

---

## Context

CB (Packaging & Distribution Advisor) has completed research and produced a
phase specification for making `zenoh_dart` consumable via pubspec.yaml path
dependencies. The full spec is at:

```
docs/phases/phase-P1-packaging.md
```

Read that file for the complete phase specification. Below is a condensed
summary of what needs to happen.

## What's Broken (3 Blockers)

1. **`linux/CMakeLists.txt`**: Only bundles `libzenoh_dart.so`, never `libzenohc.so` — Linux consumers crash at runtime
2. **`src/CMakeLists.txt:31-36`**: Hardcoded `find_library` pointing at `extern/zenoh-c/target/release` with `NO_DEFAULT_PATH` — breaks when consumed from pub.dev or path dependency without local zenoh-c build
3. **No Android zenohc**: Zero mechanism to cross-compile or provide `libzenohc.so` for Android ABIs

## What to Build

### 1. Fix CMake zenohc discovery (`src/CMakeLists.txt`)

Replace the hardcoded `find_library` block with platform-aware three-tier discovery:
- **Android**: `android/src/main/jniLibs/${ANDROID_ABI}/libzenohc.so`
- **Linux published**: `native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so`
- **Developer fallback**: `extern/zenoh-c/target/release/libzenohc.so`

Use `IMPORTED SHARED` target with `IMPORTED_NO_SONAME TRUE`. Set `RPATH` on
non-Android platforms. Use `get_filename_component(... REALPATH)` for symlink
resolution.

**Reference**: `dart_zenoh_xplr/packages/dart_zenoh/src/CMakeLists.txt`
(at `/home/hugo-bluecorn/bluecorn/CSR/git/dart_zenoh_xplr`)

### 2. Bundle libzenohc.so on Linux (`linux/CMakeLists.txt`)

Add `"${ZENOHC_LIB_DIR}/libzenohc.so"` to `zenoh_dart_bundled_libraries`.

**Reference**: `dart_zenoh_xplr/packages/dart_zenoh/linux/CMakeLists.txt`

### 3. Add Linux prebuilt (`native/linux/x86_64/libzenohc.so`)

Extract from zenoh-c v1.7.2 GitHub release standalone ZIP:
`zenoh-c-1.7.2-x86_64-unknown-linux-gnu-standalone.zip` → `lib/libzenohc.so`

### 4. Create Android build script (`scripts/build_zenoh_android.sh`)

Uses `cargo-ndk` (available at `extern/cargo-ndk`) to cross-compile zenoh-c:
```bash
RUSTUP_TOOLCHAIN=stable cargo ndk -t arm64-v8a --platform 24 \
  -o android/src/main/jniLibs build --release \
  --manifest-path extern/zenoh-c/Cargo.toml
```

Target ABIs: **arm64-v8a** (devices) + **x86_64** (emulator).

### 5. Build and commit Android prebuilts

Run the script to produce:
- `android/src/main/jniLibs/arm64-v8a/libzenohc.so`
- `android/src/main/jniLibs/x86_64/libzenohc.so`

### 6. Simplify Dart loading (`lib/src/native_lib.dart`)

Switch from two-load to single-load. Remove explicit `_openZenohc()` and
`zenohcLib`. Let the OS dynamic linker resolve libzenohc.so as a transitive
dependency of libzenoh_dart.so.

Before:
```dart
zenohcLib;  // explicit load
_bindings = ZenohDartBindings(zenohDartLib);
```

After:
```dart
_bindings = ZenohDartBindings(zenohDartLib);
// OS linker handles zenohc automatically
```

### 7. End-to-end verification

Fresh Flutter project + `zenoh_dart: path: ../zenoh_dart` in pubspec:
- `flutter run -d linux` → opens session, does put, closes
- `flutter run -d <emulator>` → same

## Key Constraints

- **Clang everywhere**: CMake + Clang on Linux, NDK Clang on Android
- **No new Dart dependencies**: Approach A uses only existing CMake/Gradle infrastructure
- **No Dart API changes**: This is purely build infrastructure
- **No C shim changes**: `src/zenoh_dart.h` and `src/zenoh_dart.c` are unchanged
- **Git-tracked prebuilts**: Commit the .so files for simplicity (Phase P1)
- **Preserve existing tests**: All session/put/delete/subscriber tests must pass

## Reference Projects

- **dart_zenoh_xplr** (`/home/hugo-bluecorn/bluecorn/CSR/git/dart_zenoh_xplr`) —
  Working Flutter FFI plugin with the exact same two-library architecture.
  The primary reference for CMake patterns, jniLibs structure, and bundled_libraries.
- **zenoh-cpp** (`extern/zenoh-cpp/cmake/helpers.cmake`) — Three-strategy
  dependency resolution pattern (conceptual model for our tiered CMake discovery)
- **cargo-ndk** (`extern/cargo-ndk`) — Cross-compilation tool for Android

## Suggested TDD Slice Decomposition

1. **CMake discovery fix** — Replace hardcoded find_library with three-tier
   discovery. Test: existing `flutter test` passes (developer fallback path).

2. **Linux bundling** — Add libzenohc.so to bundled_libraries + add prebuilt
   to `native/linux/x86_64/`. Test: `flutter build linux` output contains both
   .so files.

3. **Dart single-load** — Simplify `native_lib.dart`. Test: existing tests
   pass with single-load.

4. **Android build script** — Create `scripts/build_zenoh_android.sh`. Test:
   script produces jniLibs/{ABI}/libzenohc.so.

5. **Android integration** — Build APK with jniLibs. Test: APK contains both
   .so files for target ABIs.

6. **End-to-end** — Consumer project verification on Linux + Android.

## Important Notes for CZ

- Read the full phase spec at `docs/phases/phase-P1-packaging.md` before
  starting `/tdd-plan`
- The existing `test/session_test.dart` is the primary regression test —
  it must pass at every step
- The CMake changes are the trickiest part — study `dart_zenoh_xplr`'s
  `src/CMakeLists.txt` carefully before implementing
- `ZENOHC_LIB_DIR` must be visible in both `src/CMakeLists.txt` (where it's
  set) and `linux/CMakeLists.txt` (where it's consumed) — CMake variable
  scoping matters here since linux/ does `add_subdirectory(../src)`
- The Android build script requires: Rust (stable), Android NDK (r23+),
  cargo-ndk. The user has all of these available.
- For testing the Android build, `flutter build apk` is sufficient to verify
  the .so files are bundled — actual device/emulator testing is verification
  step 9-10, not a TDD slice prerequisite
