# Changelog

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
