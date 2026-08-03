# zenoh_dart

> ## ⚠️ NOT FOR PRODUCTION
>
> **Pre-1.0 and under active development — good enough to experiment with, not to
> build a product on.** Published to make the work visible, not because it is ready.
> Linux `x86_64` and Android `armeabi-v7a`/`arm64-v8a`/`x86_64` only; Android has no
> SHM and no advanced pub/sub.

Pure Dart FFI bindings for [Eclipse Zenoh](https://github.com/eclipse-zenoh) — the pub/sub, query and storage protocol — wrapping [zenoh-c](https://github.com/eclipse-zenoh/zenoh-c) v1.7.2 via a thin C shim layer.

## Repository Layout

```
zenoh_dart/
  package/          Dart package (publish boundary)
  src/              C shim source (156 functions)
  extern/zenoh-c/   zenoh-c submodule (v1.7.2)
  scripts/          Build scripts (Android cross-compilation)
  CMakeLists.txt    Root superbuild
  CMakePresets.json Platform presets
```

The Dart package lives in `package/`. All `dart` commands run from there. Build infrastructure lives at the repo root, outside the publish boundary.

## Prerequisites

- Dart SDK ^3.12.2
- CMake 3.21+, Ninja, Clang/Clang++
- Rust 1.85.0 (`rustup toolchain install 1.85.0`)
- For Android: Android NDK, [cargo-ndk](https://github.com/bbqsrc/cargo-ndk) (`cargo install cargo-ndk`)

## Building

### Linux (full build)

```bash
git submodule update --init
cmake --preset linux-x64
cmake --build --preset linux-x64 --target install
```

The superbuild does two things:

1. **cargo** builds `libzenohc.so` from Rust source (~3 min first time, incremental thereafter)
2. **CMake/Clang** builds `libzenoh_dart.so` (the C shim, ~2s)

Both are installed to `package/native/linux/x86_64/`. `libzenoh_dart.so` carries `RUNPATH=$ORIGIN`, which is what lets the OS linker resolve `libzenohc.so` from the same directory without `LD_LIBRARY_PATH`. `libzenohc.so` itself carries no run-time search path.

### Android

```bash
./scripts/build_zenoh_android.sh                  # arm64-v8a + x86_64
./scripts/build_zenoh_android.sh --abi arm64-v8a  # single ABI
./scripts/build_zenoh_android.sh --all            # all 4 ABIs
```

The script performs two cross-compilation steps per ABI:

1. **cargo-ndk** cross-compiles `libzenohc.so` from Rust targeting the Android ABI
2. **CMake + NDK toolchain** cross-compiles `libzenoh_dart.so` (C shim)

Both end up in `package/native/android/<abi>/`. The Flutter build hook bundles the correct ABI's `.so` files into the APK at build time.

**Supported ABIs:**

| ABI | Architecture | Use case | Shipped |
|-----|-------------|----------|---------|
| `arm64-v8a` | 64-bit ARM | Real phones (99% of devices) | yes |
| `x86_64` | 64-bit Intel | Android emulator on x86 host | yes |
| `armeabi-v7a` | 32-bit ARM | Legacy phones (pre-2015) | yes |
| `x86` | 32-bit Intel | Old emulators | no |

The published package ships the three ABIs `flutter build apk` targets by default —
`armeabi-v7a`, `arm64-v8a` and `x86_64`. The script's own default (no flag) builds only
`arm64-v8a` + `x86_64`, so `armeabi-v7a` needs its own `--abi armeabi-v7a` run; `--all` adds
`x86` as well, which is not shipped.

**Note:** The `Cannot set "ZENOHC_LIB_DIR": current scope has no parent` warning during the Android C shim build is cosmetic — `set(... PARENT_SCOPE)` in `src/CMakeLists.txt` has no parent when built standalone. It does not affect the output.

## Usage

See [`package/README.md`](package/README.md) for the Dart API documentation, examples, and CLI usage.

## Running Tests

```bash
cd package && fvm dart test --concurrency=1
```

`--concurrency=1` is required, not a preference — these tests open real zenoh sessions that contend for the network and for peer discovery.

The 571 integration tests call through the real `libzenoh_dart.so` -> `libzenohc.so` via FFI — no mocks. They open zenoh sessions in peer mode, do pub/sub over TCP with two sessions in the same process, test key expressions (including intersects/includes/equals matching), put/delete, publisher lifecycle (including express mode), SHM alloc/write/publish, scout/info, get/queryable query/reply, SHM get/reply, pull subscriber ring buffer, declared querier with matching status, liveliness token/subscriber/get, background subscriber, ZBytes clone/toBytes, ping/pong latency benchmarks, SHM ping zero-copy benchmarks, throughput benchmarks (heap and SHM), bytes serialization/deserialization (ZSerializer, ZDeserializer, ZBytesWriter, slice iterator, convenience methods), in-memory storage (subscriber + queryable + key expression intersection), advanced pub/sub (cache, history recovery, miss detection, heartbeats), byte-exact binary payloads and attachments (with attachment + encoding send options and error replies), and inter-process scenarios. Two currently fail on hosts whose locked-memory limit is below 32 MB — see Known issues in [`package/README.md`](package/README.md).

Tests run against the Linux native libraries on the host machine. Android `.so` files cannot be tested on a Linux host — the `arm64-v8a` build targets a different architecture, and even the `x86_64` build, which is the *same* architecture as the host, is linked against bionic libc and the Android dynamic linker. They are validated by deploying a Flutter app to a real device or emulator. SHM features are excluded on Android.

## License

Apache 2.0 — see [LICENSE](LICENSE).
