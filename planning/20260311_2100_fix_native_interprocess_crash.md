# Fix @Native Inter-Process Crash via Hybrid DynamicLibrary.open() Pre-load

**Created:** 2026-03-11T21:00:00Z
**Feature:** Critical bugfix — pre-load native libraries via DynamicLibrary.open() before @Native triggers
**Design Spec:** docs/design/fix-rtld-local-interprocess-crash.md (original spec; fix approach revised)

---

## Feature-Analysis/Overview

After the hooks migration (PR #18), `@Native` loads `libzenohc.so` via its lazy loading mechanism which detaches the thread from the isolate (`NoActiveIsolateScope`) and resolves symbols on background threads. When two separate Dart processes both load zenoh and connect via TCP, this causes SIGSEGV crashes. The original hypothesis (RTLD_LOCAL visibility) was disproven by A/B testing: `DynamicLibrary.open()` with the same .so files works; `@Native` crashes.

The fix: keep `@Native` annotations for bindings but pre-load both libraries eagerly via `DynamicLibrary.open()` in `ensureInitialized()` before any `@Native` call triggers. The wrong-fix C shim function `zd_promote_zenohc_global()` is reverted.

## Slice Decomposition

### Slice 1: Revert wrong fix + DynamicLibrary.open() pre-load + consolidate tests
- **Source:** `native_lib.dart`, `zenoh_dart.{h,c}`
- **Tests:** `native_lib_test.dart` (6 tests)
- **Key:** Remove zd_promote_zenohc_global, add DynamicLibrary.open() with Option C path resolution, delete promote_test.dart, rebuild C shim

### Slice 2: Inter-process TCP connection tests
- **Source:** `test/helpers/interprocess_connect.dart` (existing from 2df31a0/ab77d5f)
- **Tests:** `test/interprocess_test.dart` (4 tests)
- **Key:** Remove skip annotations, validate two Dart VMs connect without crash

### Slice 3: Inter-process pub/sub data exchange tests
- **Source:** `test/helpers/interprocess_pubsub.dart` (new)
- **Tests:** `test/interprocess_test.dart` extended (3 tests)
- **Key:** Payload round-trip across processes, binary data, multi-message

## Decisions

1. Option C path resolution: construct `.dart_tool/lib/` path from package root via `Isolate.resolvePackageUri()`
2. Transitive loading: DT_NEEDED + RPATH=$ORIGIN means loading libzenoh_dart.so loads libzenohc.so automatically
3. Revert zd_promote_zenohc_global (wrong fix) — C shim count stays at 62
4. Helper scripts accept --port/--key/--mode CLI args (no hardcoded ports)
5. Port range 19xxx for inter-process tests

## Test Summary

| Slice | New Tests | Total |
|-------|-----------|-------|
| 1 | 6 | ~185 |
| 2 | 4 | ~189 |
| 3 | 3 | ~192 |
