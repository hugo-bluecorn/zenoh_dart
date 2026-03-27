# Changelog

All notable changes to this project will be documented in this file.

## 0.12.0 — Phase 12: Ping/Pong Latency Benchmark

- **Background subscriber**: `Session.declareBackgroundSubscriber()` returns `Stream<Sample>` (fire-and-forget, lives until session closes)
- **Publisher express mode**: `isExpress` parameter on `Session.declarePublisher()` disables batching for low-latency publish
- **ZBytes read operations**: `clone()` (shallow ref-counted copy), `toBytes()` (read content as `Uint8List`)
- **CLI examples**: `z_ping.dart` (latency measurement), `z_pong.dart` (echo responder)
- 92 C shim functions, 372 integration tests

## 0.11.0 — Phase 11: Liveliness

- **Liveliness token**: `Session.declareLivelinessToken()` announces entity presence
- **Liveliness subscriber**: `Session.declareLivelinessSubscriber()` with `history` option
- **Liveliness get**: `Session.livelinessGet()` queries alive tokens
- **CLI examples**: `z_liveliness.dart`, `z_sub_liveliness.dart`, `z_get_liveliness.dart`
- 88 C shim functions, 340 integration tests

## 0.10.0 — Phase 10: Declared Querier

- **Querier**: `Session.declareQuerier()` for repeated queries with `get()`, `matchingStatus`, `hasMatchingQueryables()`
- **CLI example**: `z_querier.dart`
- 83 C shim functions, 310 integration tests

## 0.9.0 — Phase 9: Pull Subscriber

- **PullSubscriber**: `Session.declarePullSubscriber()` with C-side ring buffer and synchronous `tryRecv()`
- Configurable `capacity` (lossy: drops oldest on overflow)
- **CLI example**: `z_pull.dart`
- 77 C shim functions, 282 integration tests

## 0.7.0 — Phase 7: SHM Get/Queryable

- `Session.get()` and `Query.replyBytes()` widened to accept `ZBytes` (SHM zero-copy)
- `ZBytes.isShmBacked` property detects SHM-backed bytes
- **CLI examples**: `z_get_shm.dart`, `z_queryable_shm.dart`
- 73 C shim functions, 262 integration tests

## 0.6.0 — Phase 6: Get/Queryable

- **Get**: `Session.get()` returns `Stream<Reply>`
- **Queryable**: `Session.declareQueryable()` returns `Queryable` delivering `Stream<Query>`
- `Query`, `Reply`, `ReplyError`, `QueryTarget`, `ConsolidationMode` types
- **CLI examples**: `z_get.dart`, `z_queryable.dart`
- 72 C shim functions, 237 integration tests

## 0.5.0 — Phase 5: Scout/Info

- `ZenohId`, `WhatAmI`, `Hello` classes
- `Session.zid`, `routersZid()`, `peersZid()`
- `Zenoh.scout()` network discovery
- **CLI examples**: `z_info.dart`, `z_scout.dart`
- 62 C shim functions, 185 integration tests

## 0.4.0 — Phase 4: SHM Provider

- `ShmProvider`, `ShmMutBuffer` with zero-copy alloc/write/publish
- SHM-published data received transparently by standard subscribers
- **CLI example**: `z_pub_shm.dart`
- 56 C shim functions, 148 integration tests

## 0.3.0 — Phase 3: Publisher

- `Publisher` with `put`/`putBytes`/`deleteResource`/`matchingStatus`
- `Encoding`, `CongestionControl`, `Priority` types
- **CLI example**: `z_pub.dart`
- 43 C shim functions, 120 integration tests

## 0.2.0 — Phase 2: Subscriber

- `Session.declareSubscriber()` returns `Subscriber` with `Stream<Sample>`
- NativePort callback bridge for async sample delivery
- **CLI example**: `z_sub.dart`
- 34 C shim functions, 80 integration tests

## 0.1.0 — Phase 1: Put/Delete

- `Session.put()`, `Session.putBytes()`, `Session.deleteResource()`
- **CLI examples**: `z_put.dart`, `z_delete.dart`
- 31 C shim functions, 56 integration tests

## 0.0.1 — Phase 0: Bootstrap

- `Zenoh`, `Config`, `Session`, `KeyExpr`, `ZBytes` core classes
- `DynamicLibrary.open()` loading with build hook distribution
- 29 C shim functions, 33 integration tests
