# Phase 1: Put and Delete Operations — Planning Archive

**Feature:** One-shot put and delete operations on Session
**Created:** 2026-03-04
**Phase doc:** `docs/phases/phase-01-put-delete.md`

---

## Research Summary

### C API Contract

**zd_put** wraps `z_put()` with NULL options:
- Parameters: `z_loaned_session_t*`, `z_loaned_keyexpr_t*`, `z_owned_bytes_t*`
- Payload converted via `z_bytes_move()` — consumed unconditionally (even on error)
- Returns 0 on success, non-zero on error
- Confirmed by `extern/zenoh-c/tests/z_api_drop_options.c` lines 38-44

**zd_delete** wraps `z_delete()` with NULL options:
- Parameters: `z_loaned_session_t*`, `z_loaned_keyexpr_t*`
- Fire-and-forget semantics — deleting non-existent key succeeds
- Returns 0 on success, non-zero on error

### Deferred Options Fields

**z_put_options_t:** encoding (Phase 3), congestion_control (Phase 14), priority (Phase 14), is_express (Phase 12), timestamp (Phase 18), attachment (TBD), allowed_destination (TBD), reliability (unstable, TBD), source_info (unstable, TBD)

**z_delete_options_t:** congestion_control (Phase 14), priority (Phase 14), is_express (Phase 12), timestamp (Phase 18), reliability (unstable, TBD), allowed_destination (TBD)

### Naming Decisions

- `deleteResource` (not `delete`) — Dart reserved word; matches zenoh-cpp `delete_resource()`
- CLI `--value` flag (not `--payload`) — matches zenoh-c example convention

### Existing Patterns Referenced

- `Config.markConsumed()` in `packages/zenoh/lib/src/config.dart` — pattern for ZBytes consumption
- `Session._closed` flag in `packages/zenoh/lib/src/session.dart` — needs `_ensureOpen()` guard
- `KeyExpr` disposal via try/finally — pattern for temporary keyexpr cleanup

---

## Slice Decomposition

| Slice | Name | Tests | Depends | Blocks |
|-------|------|-------|---------|--------|
| 1 | C shim + Dart put/putBytes + build system | 7 | Phase 0 | 2, 3, 4 |
| 2 | C shim + Dart deleteResource | 4 | 1 | 4 |
| 3 | CLI z_put.dart | 3 | 1 | — |
| 4 | CLI z_delete.dart | 3 | 2 | — |
| **Total** | | **17** | | |

---

## Architectural Decisions

1. Payload consumed unconditionally — `markConsumed()` called before checking return code
2. `_ensureOpen()` guard on Session — all three methods check first
3. Temporary KeyExpr cleanup via finally — possible `_withKeyExpr` helper deferred to REFACTOR
4. C shim functions are one-liners forwarding to z_put/z_delete with NULL options
