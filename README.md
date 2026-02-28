# Zenoh Dart

Pure Dart FFI bindings for [Zenoh](https://zenoh.io/) — a pub/sub/query protocol for real-time, distributed systems.

## Architecture

```
┌─────────────────────────────┐
│   Dart API (packages/zenoh)  │  Config, Session, KeyExpr, ZBytes
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

Phases 1–18 are specified in [`docs/phases/`](docs/phases/) but not yet implemented.

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

## Phase Roadmap

| Phase | Name | Description |
|-------|------|-------------|
| 0 | [Bootstrap](docs/phases/phase-00-bootstrap.md) | Session, Config, KeyExpr, ZBytes infrastructure |
| 1 | [Put / Delete](docs/phases/phase-01-put-delete.md) | Basic key-value put and delete operations |
| 2 | [Subscribe](docs/phases/phase-02-sub.md) | Subscriber for receiving publications |
| 3 | [Publish](docs/phases/phase-03-pub.md) | Publisher with matched listener support |
| 4 | [SHM Pub/Sub](docs/phases/phase-04-shm-pub-sub.md) | Shared-memory pub/sub for zero-copy |
| 5 | [Scout / Info](docs/phases/phase-05-scout-info.md) | Network discovery and session info |
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
