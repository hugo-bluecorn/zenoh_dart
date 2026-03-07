# Zenoh Dart

Pure Dart FFI bindings for [Zenoh](https://zenoh.io/) — a pub/sub/query protocol for real-time, distributed systems.

## Architecture

```
┌─────────────────────────────┐
│   Dart API (packages/zenoh)  │  Config, Session, Publisher, Subscriber, Sample, Encoding, CongestionControl, Priority, KeyExpr, ZBytes, ShmProvider, ShmMutBuffer, ZenohId, WhatAmI, Hello
├─────────────────────────────┤
│   Generated FFI Bindings     │  bindings.dart (auto-generated via ffigen)
├─────────────────────────────┤
│   C Shim (src/zenoh_dart.c)  │  zd_* functions flattening zenoh-c macros
├─────────────────────────────┤
│   libzenohc.so (zenoh-c)     │  Rust-based zenoh implementation
└─────────────────────────────┘
```

## Current Status

**Phase 0 — Bootstrap: COMPLETE**

- 29 C shim functions wrapping zenoh-c v1.7.2
- 5 Dart API classes: `Config`, `Session`, `KeyExpr`, `ZBytes`, `ZenohException`
- 33 integration tests passing

**Phase 1 — Put/Delete: COMPLETE**

- 31 C shim functions (added `zd_put`, `zd_delete`)
- `Session.put()`, `Session.putBytes()`, `Session.deleteResource()` one-shot operations
- CLI examples: `z_put.dart`, `z_delete.dart`
- 56 integration tests passing

**Phase 2 — Subscribe: COMPLETE**

- 34 C shim functions (added `zd_declare_subscriber`, `zd_subscriber_drop`, `zd_subscriber_sizeof`)
- `Session.declareSubscriber()` returns a `Subscriber` with `Stream<Sample>` delivery via NativePort callback bridge
- `Sample` class with `keyExpr`, `payload` (UTF-8 string), `payloadBytes` (`Uint8List` raw bytes), `kind`, `attachment` fields; `SampleKind` enum (`put`, `delete`)
- CLI example: `z_sub.dart`
- 80 integration tests passing

**Phase 3 — Publisher: COMPLETE**

- 43 C shim functions (added 9 publisher functions: `zd_publisher_sizeof`, `zd_declare_publisher`, `zd_publisher_loan`, `zd_publisher_drop`, `zd_publisher_put`, `zd_publisher_delete`, `zd_publisher_keyexpr`, `zd_publisher_declare_background_matching_listener`, `zd_publisher_get_matching_status`)
- `Session.declarePublisher()` returns a `Publisher` with `put()`, `putBytes()`, `deleteResource()`, `keyExpr`, `hasMatchingSubscribers()`, `matchingStatus` stream, and `close()`
- `Encoding` class (10 MIME constants), `CongestionControl` enum, `Priority` enum
- `Sample.encoding` field for subscriber encoding extraction
- CLI example: `z_pub.dart`
- 120 integration tests passing

**Phase 4 — SHM Pub/Sub: COMPLETE**

- 56 C shim functions (added 13 `zd_shm_*` functions guarded by `Z_FEATURE_SHARED_MEMORY`/`Z_FEATURE_UNSTABLE_API`)
- `ShmProvider` class with `alloc()`, `allocGcDefragBlocking()`, `available`, and `close()`
- `ShmMutBuffer` class with `data` pointer (zero-copy write), `length`, `toBytes()` (zero-copy conversion to `ZBytes`), and `dispose()`
- SHM-published data received transparently by standard subscribers via `Publisher.putBytes()`
- CLI example: `z_pub_shm.dart`
- 148 integration tests passing

**Phase 5 — Scout / Info: COMPLETE**

- 62 C shim functions (added 6 `zd_info_*`/`zd_scout`/`zd_id_to_string`/`zd_whatami_to_view_string` functions)
- `ZenohId` class: 16-byte identifier with `toHexString()`, equality, and hashCode
- `WhatAmI` enum: `router`, `peer`, `client` values mapping zenoh-c bitmask
- `Hello` class: scouting result with `zid`, `whatami`, and `locators` fields
- `Session.zid`, `Session.routersZid()`, `Session.peersZid()` for session info queries
- `Zenoh.scout()`: discovers zenoh entities on the network via NativePort callback bridge
- CLI examples: `z_info.dart`, `z_scout.dart`
- 185 integration tests passing

Phases 6–18 are specified in [`docs/phases/`](docs/phases/) but not yet implemented.

## Packages

| Package | Path | Description |
|---------|------|-------------|
| `zenoh` | `packages/zenoh/` | Pure Dart FFI bindings for zenoh |

## Prerequisites

- [FVM](https://fvm.app/) (Flutter Version Manager) — Dart/Flutter are managed via FVM, not system PATH
- Dart SDK ^3.11.0 (installed via FVM)
- For building native libraries: clang, cmake, ninja, Rust (stable, MSRV 1.75.0)

## Quick Start

### 1. Build zenoh-c

```bash
cmake -S extern/zenoh-c -B extern/zenoh-c/build -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=TRUE \
  -DZENOHC_BUILD_IN_SOURCE_TREE=TRUE

RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release
```

### 2. Build C shim

```bash
cmake -S src -B build -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build
```

### 3. Run tests

```bash
cd packages/zenoh
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build fvm dart test
```

### 4. Try the CLI examples

> **Note:** `LD_LIBRARY_PATH` is required during development because the native
> libraries (`libzenoh_dart.so`, `libzenohc.so`) are not on the system linker
> path. This applies to both tests and CLI examples.

```bash
# Put data on a key expression
cd packages/zenoh
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'

# Delete a key expression
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_delete.dart -k demo/example/test

# Subscribe to a key expression (runs until Ctrl-C; combine with z_put or z_pub in another terminal)
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_sub.dart -k 'demo/example/**'

# Publish in a loop on a key expression (runs until Ctrl-C)
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_pub.dart -k demo/example/test -p 'Hello from Dart!'

# Publish via shared memory in a loop on a key expression (runs until Ctrl-C)
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_pub_shm.dart -k demo/example/test -p 'Hello from SHM!'

# Print own session ZID and connected router/peer ZIDs
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_info.dart

# Discover zenoh entities on the network (scouts for routers, peers, and clients)
LD_LIBRARY_PATH=../../extern/zenoh-c/target/release:../../build \
  fvm dart run example/z_scout.dart
```

## Phase Roadmap

| Phase | Name | Description |
|-------|------|-------------|
| 0 | [Bootstrap](docs/phases/phase-00-bootstrap.md) | Session, Config, KeyExpr, ZBytes infrastructure — **COMPLETE** |
| 1 | [Put / Delete](docs/phases/phase-01-put-delete.md) | Basic key-value put and delete operations — **COMPLETE** |
| 2 | [Subscribe](docs/phases/phase-02-sub.md) | Subscriber for receiving publications — **COMPLETE** |
| 3 | [Publish](docs/phases/phase-03-pub.md) | Publisher with matched listener support — **COMPLETE** |
| 4 | [SHM Pub/Sub](docs/phases/phase-04-shm-pub-sub.md) | Shared-memory pub/sub for zero-copy — **COMPLETE** |
| 5 | [Scout / Info](docs/phases/phase-05-scout-info.md) | Network discovery and session info — **COMPLETE** |
| 6 | [Get / Queryable](docs/phases/phase-06-get-queryable.md) | Request/reply query pattern |
| 7 | [SHM Get/Queryable](docs/phases/phase-07-shm-get-queryable.md) | Shared-memory queries |
| 8 | [Channels](docs/phases/phase-08-channels.md) | Channel-based message delivery |
| 9 | [Pull](docs/phases/phase-09-pull.md) | Pull-mode subscriber |
| 10 | [Querier](docs/phases/phase-10-querier.md) | Dedicated querier abstraction |
| 11 | [Liveliness](docs/phases/phase-11-liveliness.md) | Liveliness tokens and subscribers |
| 12 | [Ping/Pong](docs/phases/phase-12-ping-pong.md) | Latency measurement tools |
| 13 | [SHM Ping](docs/phases/phase-13-shm-ping.md) | Shared-memory ping/pong |
| 14 | [Throughput](docs/phases/phase-14-throughput.md) | Throughput measurement tools |
| 15 | [SHM Throughput](docs/phases/phase-15-shm-throughput.md) | Shared-memory throughput |
| 16 | [Bytes](docs/phases/phase-16-bytes.md) | Advanced serialization/deserialization |
| 17 | [Storage](docs/phases/phase-17-storage.md) | In-memory storage backend |
| 18 | [Advanced](docs/phases/phase-18-advanced.md) | Advanced pub/sub with history |

## Development

```bash
# Bootstrap monorepo
fvm dart run melos bootstrap

# Run analysis
fvm dart analyze packages/zenoh

# Regenerate FFI bindings (after modifying src/zenoh_dart.h)
cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml
```

## License

See [LICENSE](LICENSE) for details.
