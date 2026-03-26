## 0.9.0

### Added
- `Session.declarePullSubscriber()` returns `PullSubscriber` with synchronous `tryRecv()` polling via ring buffer
- `PullSubscriber` class with `tryRecv()` (returns `Sample?`), `keyExpr`, `close()`, and configurable ring buffer `capacity` (lossy: drops oldest on overflow)
- 4 new C shim functions (73 → 77 total)
- CLI example: `z_pull.dart` (interactive stdin polling)
- 20 new integration tests (262 → 282 total)

## 0.8.0

### Changed
- `Session.get()` payload parameter widened from `Uint8List?` to `ZBytes?` — accepts SHM-backed bytes for zero-copy query payloads
- `Query.replyBytes()` payload parameter widened from `Uint8List` to `ZBytes` — accepts SHM-backed bytes for zero-copy reply payloads

### Added
- `ZBytes.isShmBacked` property — detects whether bytes are backed by shared memory
- 1 new C shim function `zd_bytes_is_shm()` (72 → 73 total)
- CLI examples: `z_get_shm.dart`, `z_queryable_shm.dart`
- 25 new integration tests (237 → 262 total)

## 0.7.0

### Added
- `Session.get()` returns `Stream<Reply>` with selector, parameters, payload, encoding, target, consolidation, and timeout options
- `Session.declareQueryable()` returns `Queryable` with `stream`, `keyExpr`, `close()`, and `complete` flag
- `Query` class with `reply()`, `replyBytes()`, `dispose()`, `keyExpr`, `parameters`, `payloadBytes` — supports multiple replies per query
- `Reply` tagged union with `isOk`, `ok` (Sample), `error` (ReplyError) accessors
- `ReplyError` class with `payloadBytes`, `payload`, `encoding` fields
- `QueryTarget` enum: bestMatching, all, allComplete
- `ConsolidationMode` enum: auto, none, monotonic, latest
- 10 new C shim functions (62 → 72 total)
- CLI examples: `z_get.dart`, `z_queryable.dart`
- 44 new integration tests (193 → 237 total)

## 0.0.1

Initial release — Phases 0-5 complete.

- **62 C shim functions** wrapping zenoh-c v1.7.2
- **18 Dart API classes**: Zenoh, Config, Session, KeyExpr, ZBytes, Publisher, Subscriber, Sample, SampleKind, Encoding, CongestionControl, Priority, ShmProvider, ShmMutBuffer, ZenohId, WhatAmI, Hello, ZenohException
- **7 CLI examples**: z_put, z_delete, z_sub, z_pub, z_pub_shm, z_info, z_scout
- **193 integration tests** including inter-process TCP validation
- Shared memory zero-copy publishing (Linux)
- Network scouting and session info
- Build hooks for native library distribution (Linux x86_64, Android arm64-v8a/x86_64)
- DynamicLibrary.open() loading (avoids @Native inter-process crashes)
