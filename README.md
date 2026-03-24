# zenoh_dart

Pure Dart FFI bindings for the [Zenoh](https://zenoh.io/) pub/sub/query protocol, wrapping [zenoh-c](https://github.com/eclipse-zenoh/zenoh-c) v1.7.2 via a thin C shim layer.

## Repository Layout

```
zenoh_dart/
  package/          Dart package (publish boundary)
  src/              C shim source
  extern/zenoh-c/   zenoh-c submodule (v1.7.2)
  scripts/          Build scripts (Android cross-compilation)
  CMakeLists.txt    Root superbuild
  CMakePresets.json Platform presets
```

The Dart package lives in `package/`. All `fvm dart` commands run from there. Build infrastructure lives at the repo root, outside the publish boundary.

## Prerequisites

- [FVM](https://fvm.app/) (Flutter Version Management) — `fvm dart` / `fvm flutter`
- CMake 3.16+, Ninja, Clang/Clang++
- Rust 1.85.0 (`rustup toolchain install 1.85.0`)
- For Android: Android NDK, [cargo-ndk](https://github.com/nicholasrq/cargo-ndk)

## Building

### Linux (full build)

```bash
cmake --preset linux-x64
cmake --build --preset linux-x64 --target install
```

This builds zenoh-c from source via cargo (~3 min first time), compiles the C shim, and installs both `.so` files to `package/native/linux/x86_64/`.

### Android

```bash
./scripts/build_zenoh_android.sh                  # arm64-v8a + x86_64
./scripts/build_zenoh_android.sh --abi arm64-v8a  # single ABI
```

## Usage

See [`package/README.md`](package/README.md) for the Dart API documentation, examples, and CLI usage.

## Running Tests

```bash
cd package && fvm dart test
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
