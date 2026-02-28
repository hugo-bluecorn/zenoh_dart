# Changelog

## 0.1.0 (Unreleased)

### Added
- Build system: CMakeLists.txt links C shim against libzenohc.so with three-tier discovery (Android, Linux prebuilt, developer fallback)
- C shim (`src/zenoh_dart.{h,c}`): 29 FFI-friendly functions wrapping zenoh-c v1.7.2 (config, session, keyexpr, bytes, string utilities)
- Dart SDK headers (`src/dart/`) compiled into libzenoh_dart.so for NativePort support
- ffigen configuration with zenoh-c include paths and opaque type mappings
- `Config` class: default config creation, JSON5 insertion, dispose, consumed-state tracking
- `Session` class: open (with optional config), graceful close, consumed-config safety
- `KeyExpr` class: create from string, value getter, dispose (dual native allocation cleanup)
- `ZBytes` class: fromString, fromUint8List, toStr round-trip, dispose
- `ZenohException` class with message and return code
- Barrel export (`packages/zenoh/lib/zenoh.dart`) for all public types
- 33 integration tests validating the full Dart → FFI → C shim → zenoh-c stack

## 0.0.1 (Unreleased)

- Initial scaffold: Melos monorepo with pure Dart `zenoh` package
