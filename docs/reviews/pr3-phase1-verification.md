## CA Verification

**Phase 1: z_put + z_delete (One-shot Publish)**

### Test Delta
- Before: 39 tests (Phase 0 hardened)
- After: 56 tests (+17)
- Analyzer: 0 warnings

### Slices: 4/4 complete

| Slice | Planned Tests | Actual | Status |
|-------|--------------|--------|--------|
| 1 — put/putBytes + build | 7 | 7 | PASS |
| 2 — deleteResource | 4 | 4 | PASS |
| 3 — z_put CLI | 3 | 3 | PASS |
| 4 — z_delete CLI | 3 | 3 | PASS |

### Key Implementation Decisions
- `_withKeyExpr` helper extracted during refactor — eliminates try/finally duplication across all three methods
- C shim uses `z_put_options_default(&opts)` instead of `NULL` — defensive, ready for future options
- `ZBytes.dispose()` short-circuits on consumed payloads (prevents double-free)
- `putBytes` validates payload state before creating KeyExpr (fail-fast)

### Deviations from Plan
- CLI `--value` flag renamed to `--payload` post-implementation to match zenoh-c convention (commit `8721da8`)
- PR base retargeted from stale `feature/phase0-bootstrap` to `main`

### Acceptance Criteria
- All 17 planned tests present and passing
- Payload consumption semantics correct (`markConsumed()` before error check)
- Temporary KeyExpr cleanup via `_withKeyExpr` finally block
- `_ensureOpen()` guard on all Session operations
- `deleteResource` naming matches C++ `delete_resource()`
- CLI examples mirror zenoh-c z_put.c / z_delete.c
