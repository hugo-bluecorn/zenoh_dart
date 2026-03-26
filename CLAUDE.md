# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pure Dart FFI package providing bindings for [Zenoh](https://zenoh.io/) (a pub/sub/query protocol) via a C shim layer wrapping zenoh-c v1.7.2.

## Repository Structure

```
zenoh_dart/
  package/                      # PUBLISH BOUNDARY — dart pub publish runs here
    lib/                        #   Dart API
    hook/                       #   Dart build hooks (CodeAsset registration)
    native/                     #   Prebuilt shared libraries (linux/x86_64/, android/<abi>/)
    example/                    #   CLI examples (12: z_put, z_sub, z_pub, z_get, z_queryable, z_pull, etc.)
    test/                       #   Integration tests (282 tests)
    pubspec.yaml
  src/                          # C shim source (outside publish boundary)
    zenoh_dart.{h,c}
    CMakeLists.txt
    dart/                       #   Dart API DL headers
  extern/
    zenoh-c/                    # Only submodule — pinned at v1.7.2
  scripts/
    build_zenoh_android.sh      # Android cross-compilation
  CMakeLists.txt                # Root superbuild
  CMakePresets.json             # Platform presets
```

## FVM Requirement

**Dart and Flutter are NOT on PATH.** ALL commands must use `fvm`:

```bash
fvm dart ...
fvm flutter ...
```

## Build & Development Commands

### Native library build (Linux)

```bash
# Full build: zenoh-c from source + C shim + install to package/native/
git submodule update --init
cmake --preset linux-x64
cmake --build --preset linux-x64 --target install
```

First build takes ~3 minutes (cargo). Subsequent builds are incremental (~2s for C shim changes).

**Rust version constraint:** zenoh-c 1.7.2 requires Rust 1.85.0 — Rust >= 1.86 breaks `static_init`. The preset pins `+1.85.0` via `ZENOHC_CARGO_CHANNEL`. Install with `rustup toolchain install 1.85.0`.

**C shim only** (when zenoh-c is already built):
```bash
cmake --preset linux-x64-shim-only
cmake --build --preset linux-x64-shim-only --target install
```

### Android cross-compilation

```bash
./scripts/build_zenoh_android.sh                  # arm64-v8a + x86_64
./scripts/build_zenoh_android.sh --abi arm64-v8a  # single ABI
```

SHM features are excluded on Android.

### Dart package commands

```bash
# Regenerate FFI bindings after modifying src/zenoh_dart.h
cd package && fvm dart run ffigen --config ffigen.yaml

# Analyze Dart code
cd package && fvm dart analyze

# Run all tests
cd package && fvm dart test

# Run a single test file
cd package && fvm dart test test/session_test.dart
```

### CLI examples

```bash
cd package && fvm dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'
cd package && fvm dart run example/z_delete.dart -k demo/example/test
cd package && fvm dart run example/z_sub.dart -k 'demo/example/**'
cd package && fvm dart run example/z_pub.dart -k demo/example/test -p 'Hello from Dart!'
cd package && fvm dart run example/z_pub_shm.dart -k demo/example/test -p 'Hello from SHM!'
cd package && fvm dart run example/z_info.dart
cd package && fvm dart run example/z_scout.dart
cd package && fvm dart run example/z_get.dart -s 'demo/example/**'
cd package && fvm dart run example/z_queryable.dart -k demo/example/zenoh-dart-queryable
cd package && fvm dart run example/z_get_shm.dart -s 'demo/example/**'
cd package && fvm dart run example/z_queryable_shm.dart -k demo/example/zenoh-dart-queryable
cd package && fvm dart run example/z_pull.dart -k 'demo/example/**' -s 3
```

## Architecture

**Data flow:** Dart API (`package/lib/zenoh.dart`) → Generated bindings (`package/lib/src/bindings.dart`) → Native C (`src/zenoh_dart.{h,c}`) → `libzenohc.so` (resolved by OS linker via DT_NEEDED)

### Key Conventions

- **`zd_` prefix**: All C shim symbols use `zd_` to avoid collisions with zenoh-c's `z_`/`zc_` namespace.
- **Binding generation**: `package/lib/src/bindings.dart` is auto-generated — never edit manually. Regenerate with `fvm dart run ffigen --config ffigen.yaml` after changing `src/zenoh_dart.h`.
- **`DynamicLibrary.open()` loading**: `native_lib.dart::ensureInitialized()` resolves `libzenoh_dart.so` via `Isolate.resolvePackageUriSync()` and loads eagerly. On Android, bare `DynamicLibrary.open('libzenoh_dart.so')` is used. Do NOT use `@Native` annotations — they cause tokio waker vtable crashes in multi-process TCP scenarios.
- **Build hook**: `package/hook/build.dart` registers CodeAsset entries for distribution. The hook is target-aware (Linux/Android).
- **Entity lifecycle**: sizeof → declare → loan → operations → drop/close. Idempotent close, StateError after close.

### Available Dart API classes

- `Zenoh` — Static utilities: `initLog()`, `scout()`
- `Config` — Session configuration with JSON5 insertion
- `Session` — Open/close sessions; `put`, `putBytes`, `deleteResource`, `declareSubscriber`, `declarePublisher`, `get`, `declareQueryable`, `declarePullSubscriber`, `zid`, `routersZid()`, `peersZid()`
- `KeyExpr` — Key expression creation and validation
- `ZBytes` — Binary payload container; `isShmBacked` detects SHM backing
- `Publisher` — Declared publisher with `put`/`putBytes`/`deleteResource`/`matchingStatus`
- `Subscriber` — Callback-based subscriber delivering `Stream<Sample>`
- `PullSubscriber` — Ring-buffer-backed pull subscriber with `tryRecv()` (lossy, drops oldest)
- `Query` — Received query with `reply()`/`replyBytes()`/`dispose()`, `keyExpr`, `parameters`, `payloadBytes`
- `Queryable` — Callback-based queryable delivering `Stream<Query>`
- `Reply` — Tagged union: `isOk`, `ok` (Sample), `error` (ReplyError)
- `ReplyError` — Error reply with `payloadBytes`, `payload`, `encoding`
- `QueryTarget` — Enum: `bestMatching`, `all`, `allComplete`
- `ConsolidationMode` — Enum: `auto`, `none`, `monotonic`, `latest`
- `Sample` — Received data with `keyExpr`, `payload`, `payloadBytes`, `kind`, `attachment`, `encoding`
- `SampleKind` — Enum: `put`, `delete`
- `Encoding` — MIME type wrapper with predefined constants
- `CongestionControl` — Enum: `block`, `drop`
- `Priority` — 7 priority levels
- `ShmProvider` — POSIX shared memory provider
- `ShmMutBuffer` — Mutable SHM buffer for zero-copy writes
- `ZenohId` — 16-byte session identifier
- `WhatAmI` — Enum: `router`, `peer`, `client`
- `Hello` — Scouting result
- `ZenohException` — Error type

## Linting

Uses `lints` package (configured in `package/analysis_options.yaml`).

## Contributing

### Adding a C shim function

1. Add the function declaration to `src/zenoh_dart.h` and implementation to `src/zenoh_dart.c`
2. Use the `zd_` prefix
3. Rebuild: `cmake --build --preset linux-x64 --target install`
4. Regenerate bindings: `cd package && fvm dart run ffigen --config ffigen.yaml`
5. Add Dart API wrapper in `package/lib/src/`
6. Add tests in `package/test/`
7. Run: `cd package && fvm dart test`
