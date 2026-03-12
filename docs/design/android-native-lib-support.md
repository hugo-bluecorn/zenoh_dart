# Android Native Library Support

**Status**: Spec
**Date**: 2026-03-12
**Scope**: zenoh-dart upstream — enable Android runtime for Flutter consumers
**Branch**: `feature/android-native-lib`

## Problem

`native_lib.dart`, `hook/build.dart`, and `build_zenoh_android.sh` are
Linux-only. When a Flutter app (e.g. zenoh-counter-flutter) runs on Android,
`ensureInitialized()` throws:

```
StateError: Could not find libzenoh_dart.so. Ensure the build hook has run.
```

## Background

Build hooks (`hooks` + `code_assets` packages) fully support Android. Flutter
invokes `hook/build.dart` **once per target architecture** with:

- `input.config.code.targetOS` — `OS.android`, `OS.linux`, etc.
- `input.config.code.targetArchitecture` — `Architecture.arm64`, `Architecture.x64`, etc.

Returned `CodeAsset` files are automatically placed in `jniLibs/lib/<abi>/`
via `copyNativeCodeAssetsAndroid()` in Flutter tools. No Gradle
`externalNativeBuild` or `ffiPlugin: true` needed.

At runtime on Android, `DynamicLibrary.open('libzenoh_dart.so')` (bare name,
no path) works because Android's linker searches the APK's `lib/<abi>/`
directory. `libzenohc.so` resolves transitively via DT_NEEDED (both .so files
co-located).

## Prebuilt Directory Layout

Current:
```
packages/zenoh/native/
  linux/
    x86_64/
      libzenoh_dart.so
      libzenohc.so
```

After:
```
packages/zenoh/native/
  linux/
    x86_64/
      libzenoh_dart.so
      libzenohc.so
  android/
    arm64-v8a/
      libzenoh_dart.so
      libzenohc.so
    x86_64/              # emulator
      libzenoh_dart.so
      libzenohc.so
```

## Changes

### 1. `native_lib.dart` — Android short-circuit

Add `Platform.isAndroid` check at the top of `ensureInitialized()`, before
`_resolveLibraryPath`. On Android, the APK linker handles path resolution.

```dart
void ensureInitialized() {
  if (_initialized) return;

  DynamicLibrary lib;
  if (Platform.isAndroid) {
    // Android: APK linker resolves from lib/<abi>/ automatically.
    // libzenohc.so loads transitively via DT_NEEDED.
    lib = DynamicLibrary.open('libzenoh_dart.so');
  } else {
    final libPath = _resolveLibraryPath('libzenoh_dart.so');
    if (libPath == null) {
      throw StateError(
        'Could not find libzenoh_dart.so. Ensure the build hook has run.',
      );
    }
    lib = DynamicLibrary.open(libPath);
  }

  _bindings = ZenohDartBindings(lib);

  final result = _bindings.zd_init_dart_api_dl(NativeApi.initializeApiDLData);
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }

  _initialized = true;
}
```

### 2. `hook/build.dart` — target-aware prebuilt selection

Replace the hardcoded `native/linux/x86_64/` with a switch on target OS and
architecture.

Architecture-to-directory mapping:

| `code_assets` value | Directory name |
|---------------------|----------------|
| `Architecture.arm64` | `arm64-v8a` |
| `Architecture.arm` | `armeabi-v7a` |
| `Architecture.x64` | `x86_64` |
| `Architecture.ia32` | `x86` |

```dart
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final nativeDir = _nativeDir(input.packageRoot, codeConfig);

    // Primary: C shim
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenoh_dart.so'),
      ),
    );

    // Secondary: zenoh-c runtime (resolved by OS linker via DT_NEEDED)
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenohc.so'),
      ),
    );
  });
}

Uri _nativeDir(Uri packageRoot, CodeConfig config) {
  final os = config.targetOS;
  final arch = config.targetArchitecture;

  if (os == OS.android) {
    final abi = _androidAbi(arch);
    return packageRoot.resolve('native/android/$abi/');
  }
  if (os == OS.linux) {
    // x64 → x86_64 to match uname convention
    final dirName = arch == Architecture.x64 ? 'x86_64' : arch.toString();
    return packageRoot.resolve('native/linux/$dirName/');
  }
  throw UnsupportedError('Unsupported target OS: $os');
}

String _androidAbi(Architecture arch) => switch (arch) {
  Architecture.arm64 => 'arm64-v8a',
  Architecture.arm => 'armeabi-v7a',
  Architecture.x64 => 'x86_64',
  Architecture.ia32 => 'x86',
  _ => throw UnsupportedError('Unsupported Android architecture: $arch'),
};
```

### 3. `scripts/build_zenoh_android.sh` — also build C shim

The existing script builds `libzenohc.so` only. Extend it to also cross-compile
`libzenoh_dart.so` using CMake with the NDK toolchain.

After the cargo-ndk loop, add a CMake cross-compilation step per ABI:

```bash
# ABI → NDK architecture name for CMake
declare -A ABI_TO_CMAKE_ARCH=(
  ["arm64-v8a"]="aarch64"
  ["armeabi-v7a"]="armv7"
  ["x86"]="x86"
  ["x86_64"]="x86_64"
)

for abi in "${ABIS[@]}"; do
  echo "Building C shim for ${abi}..."

  BUILD_DIR="${PROJECT_ROOT}/build/android/${abi}"
  cmake \
    -S "${PROJECT_ROOT}/src" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${abi}" \
    -DANDROID_PLATFORM="android-${API_LEVEL}" \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build "${BUILD_DIR}" --config Release

  cp "${BUILD_DIR}/libzenoh_dart.so" "${JNILIBS_DIR}/${abi}/"
  echo "Built: ${JNILIBS_DIR}/${abi}/libzenoh_dart.so"
done
```

### 4. Copy prebuilts to `native/android/<abi>/`

After the build script runs, copy both .so files to the prebuilt directory
that the build hook reads from:

```bash
for abi in "${ABIS[@]}"; do
  DEST="${PROJECT_ROOT}/packages/zenoh/native/android/${abi}"
  mkdir -p "${DEST}"
  cp "${JNILIBS_DIR}/${abi}/libzenohc.so" "${DEST}/"
  cp "${JNILIBS_DIR}/${abi}/libzenoh_dart.so" "${DEST}/"
done
```

Update the script's output dir variable from `JNILIBS_DIR` (old plugin_ffi
convention) to the `native/android/` layout, or keep `JNILIBS_DIR` as an
intermediate build output and copy to `native/android/` as a final step.

### 5. `.gitignore` — exclude Android prebuilts from git

Android prebuilts are large (~7MB per ABI) and developer-generated. Add:

```
packages/zenoh/native/android/
```

Same treatment as `native/linux/x86_64/*.so` if those are also gitignored.

## What Does NOT Change

- `src/CMakeLists.txt` — already has full Android support (tier-1 discovery,
  16k page size, no RPATH on Android)
- `packages/zenoh/pubspec.yaml` — no `ffiPlugin: true` needed; hooks handle it
- `bindings.dart` — no regeneration needed; same C shim API
- Existing 193 Linux tests — unaffected
- `packages/zenoh/lib/src/*.dart` (all API classes) — no changes

## Verification

1. **Linux regression**: `cd packages/zenoh && fvm dart test` — all 193 pass
2. **Android smoke test**: Build zenoh-counter-flutter APK, install on Pixel 9a,
   tap Connect, verify no crash. Subscribe to counter topic, verify data arrives.
3. **Emulator**: Same test on x86_64 Android emulator (if x86_64 prebuilts built)

## SHM Note

SHM (`Z_FEATURE_SHARED_MEMORY`) may not be available on Android. The zenoh-c
Cargo build would need `--features shared-memory,unstable` for cargo-ndk. If
SHM isn't needed for the counter app, skip it — the CMakeLists.txt compile
definitions (`Z_FEATURE_SHARED_MEMORY`, `Z_FEATURE_UNSTABLE_API`) are harmless
if zenoh-c was built without them (the C shim functions are `#ifdef`-guarded).

## Files Changed

| File | Change |
|------|--------|
| `packages/zenoh/lib/src/native_lib.dart` | Add `Platform.isAndroid` short-circuit |
| `packages/zenoh/hook/build.dart` | Target-aware prebuilt directory selection |
| `scripts/build_zenoh_android.sh` | Add C shim cross-compilation step |
| `.gitignore` | Add `packages/zenoh/native/android/` |
