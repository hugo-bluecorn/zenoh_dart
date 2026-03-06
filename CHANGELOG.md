# Changelog

## 0.4.0 (Unreleased)

### Added
- `Publisher` class: declared publisher with `put()`, `putBytes()`, `deleteResource()`, `keyExpr`, `hasMatchingSubscribers()`, `matchingStatus` stream, and `close()`
- `Encoding` class: MIME type wrapper with 10 predefined constants (textPlain, applicationJson, etc.) and custom constructor
- `CongestionControl` enum: `block` and `drop` congestion control strategies
- `Priority` enum: 7 priority levels from `realTime` to `background`
- `Session.declarePublisher()`: declare a publisher with optional encoding, congestionControl, priority, and enableMatchingListener
- `Sample.encoding` field: nullable String for received sample encoding (non-breaking)
- C shim subscriber callback updated to extract and post encoding as 5th Dart_CObject array element
- C shim `zd_publisher_sizeof()`, `zd_declare_publisher()`, `zd_publisher_loan()`, `zd_publisher_drop()`, `zd_publisher_put()`, `zd_publisher_delete()`, `zd_publisher_keyexpr()`, `zd_publisher_declare_background_matching_listener()`, `zd_publisher_get_matching_status()`
- CLI example `z_pub.dart`: publishes in a loop with `-k`/`--key`, `-p`/`--payload`, `-a`/`--attach`, `-e`/`--connect`, `-l`/`--listen`, `--add-matching-listener` flags
- 40 new tests (120 total) covering publisher lifecycle, put/putBytes, delete, encoding, matching status, QoS options, pub/sub integration, and CLI

## 0.3.0 (Unreleased)

### Added
- `Subscriber` class: callback-based subscriber with `Stream<Sample>` delivery via NativePort bridge pattern
- `Sample` class: received data with `keyExpr`, `payload`, `kind`, `attachment` fields
- `SampleKind` enum: `put` and `delete` sample kinds
- `Session.declareSubscriber(keyExpr)`: declare a subscriber on a key expression, returns `Subscriber`
- C shim `zd_declare_subscriber()`: declares subscriber with NativePort callback bridge (Dart_CObject array posted via Dart_PostCObject_DL)
- C shim `zd_subscriber_drop()`: undeclares and drops subscriber
- C shim `zd_subscriber_sizeof()`: returns sizeof(z_owned_subscriber_t)
- CLI example `z_sub.dart`: subscribes to key expression with `-k`/`--key`, `-e`/`--connect`, `-l`/`--listen` flags
- `-e`/`--connect` and `-l`/`--listen` flags added to `z_put.dart` for explicit endpoint configuration
- 22 new tests (80 total) covering subscriber lifecycle, NativePort bridge delivery, stream close, multi-subscriber independence, and CLI

## 0.2.0 (Unreleased)

### Added
- `Session.put(keyExpr, value)`: one-shot string publish on a key expression
- `Session.putBytes(keyExpr, payload)`: one-shot ZBytes publish with payload consumption semantics
- `Session.deleteResource(keyExpr)`: one-shot delete on a key expression (fire-and-forget)
- `Session._ensureOpen()` guard: throws `StateError` on operations after `close()`
- `ZBytes.markConsumed()` and consumed-state guard matching the `Config` pattern
- `ZBytes.nativePtr` getter with disposed/consumed guards for FFI interop
- `KeyExpr.nativePtr` getter for FFI interop
- C shim `zd_put()`: forwards to `z_put()` with default options and `z_bytes_move()` payload consumption
- C shim `zd_delete()`: forwards to `z_delete()` with default options
- CLI example `z_put.dart`: opens session, puts data with `--key`/`--payload` options, closes session
- CLI example `z_delete.dart`: opens session, deletes key with `--key` option, closes session
- 17 new tests (56 total) covering put/putBytes/deleteResource operations and CLI examples

## 0.1.0 (Unreleased)

### Added
- Build system: CMakeLists.txt compiles C shim with Dart SDK headers and links against libzenohc.so via three-tier discovery (Android jniLibs, Linux prebuilt, developer fallback) with RPATH set to $ORIGIN
- C shim (`src/zenoh_dart.{h,c}`): 29 `zd_`-prefixed FFI functions wrapping zenoh-c v1.7.2 APIs for config, session, keyexpr, bytes, and string operations
- Dart SDK headers (`src/dart/`) compiled into libzenoh_dart.so for Dart Native API DL support
- ffigen configuration (`ffigen.yaml`) with zenoh-c include paths and opaque type mappings for `z_owned_*`, `z_loaned_*`, `z_view_*`, `z_moved_*` types
- Auto-generated FFI bindings (`bindings.dart`) via dart:ffi ffigen
- Native library loader (`native_lib.dart`) with automatic Dart API DL initialization on first load
- `Config` class: default config creation, `insertJson5()` for mutable config modification, `dispose()`, consumed-state tracking with `StateError` guards
- `Session` class: `open()` factory (with optional config), graceful `close()` (z_close then z_session_drop), config consumption marking
- `KeyExpr` class: construct from string expression, `value` getter (data+len extraction, no null-termination assumption), `dispose()` freeing dual native allocations (struct + C string)
- `ZBytes` class: `fromString()`, `fromUint8List()`, `toStr()` round-trip with proper owned-string lifecycle, `dispose()`
- `ZenohException` class with message and return code for zenoh-c error propagation
- Barrel export (`packages/zenoh/lib/zenoh.dart`) for Config, Session, KeyExpr, ZBytes, ZenohException
- Logging initialization via `zd_init_log()` wrapping `zc_init_log_from_env_or()`
- Double-drop/double-close safety on all owned types (gravestone-state no-op pattern)
- Idempotent `dispose()`/`close()` guarded by `_disposed`/`_closed` flags
- 33 integration tests across 5 test files validating the full Dart → FFI → C shim → zenoh-c stack

## 0.0.1 (Unreleased)

- Initial scaffold: Melos monorepo with pure Dart `zenoh` package
