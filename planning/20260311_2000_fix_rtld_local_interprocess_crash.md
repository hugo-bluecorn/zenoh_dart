# Fix RTLD_LOCAL Inter-Process Crash

**Created:** 2026-03-11T20:00:00Z
**Feature:** Critical bugfix — promote libzenohc.so from RTLD_LOCAL to RTLD_GLOBAL
**Design Spec:** docs/design/fix-rtld-local-interprocess-crash.md

---

## Feature-Analysis/Overview

After the hooks migration (PR #18), `@Native` loads `libzenohc.so` with `RTLD_LOCAL` (dlopen default). When two separate Dart processes both load zenoh and connect via TCP, tokio's waker vtable dispatch fails because RTLD_LOCAL scopes symbols to the loading library. The fix adds `zd_promote_zenohc_global()` to re-open with `RTLD_LAZY | RTLD_GLOBAL`.

## Slice Decomposition

### Slice 1: C Shim Function and Dart Initialization Integration (Build Step)
- **Source:** `src/zenoh_dart.{h,c}`, `packages/zenoh/lib/src/native_lib.dart`
- **Tests:** None new (existing 185 tests = regression guard)
- **Key:** Add `zd_promote_zenohc_global()`, modify `ensureInitialized()`, rebuild, regenerate ffigen

### Slice 2: Inter-Process Connection Without Crash
- **Source:** `packages/zenoh/test/helpers/interprocess_connect.dart`
- **Tests:** `packages/zenoh/test/interprocess_test.dart` (3 tests)
- **Key:** Two Dart processes connect via TCP without SIGSEGV; helper accepts `--port` CLI arg

### Slice 3: Inter-Process Pub/Sub Data Exchange
- **Source:** `packages/zenoh/test/helpers/interprocess_subscriber.dart`
- **Tests:** `packages/zenoh/test/interprocess_test.dart` (3 more tests)
- **Key:** Payload round-trip across processes; helper accepts `--port` and `--key` CLI args

## Decisions

1. dlopen promotion (5-line fix) over static linking (14MB binary size increase)
2. Fail-hard on promotion failure — StateError before session crash
3. No new tests in Slice 1 — existing 185 tests exercise ensureInitialized()
4. Helper scripts accept port via CLI to avoid hardcoded port collisions
5. Port range 19xxx for inter-process tests (existing: 17xxx–18xxx)

## Test Summary

| Slice | New Tests | Total |
|-------|-----------|-------|
| 1 | 0 | 185 existing |
| 2 | 3 | 188 |
| 3 | 3 | 191 |

C shim function count: 62 → 63
