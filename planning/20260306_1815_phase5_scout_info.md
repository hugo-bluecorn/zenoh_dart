# Feature Notes: Phase 5 -- Scout/Info (Discovery & Session Info)

**Created:** 2026-03-06
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Implement network discovery (`Zenoh.scout`) and session information queries (`Session.zid`, `Session.routersZid`, `Session.peersZid`). These are essential for connection diagnostics, peer awareness, and building applications that need to know their network topology.

### Use Cases
- Application startup: verify session identity and check connected peers/routers
- Network diagnostics: discover what zenoh entities are reachable
- Connection monitoring: list connected routers and peers
- CLI tooling: `z_info` and `z_scout` mirror zenoh-c examples

### Context
Phases 0-4 established: Session open/close, KeyExpr validation, ZBytes payload, one-shot put/delete, callback-based subscriber, declared publisher with QoS, and SHM provider with zero-copy publish. Phase 5 adds discovery and session introspection -- standalone features that don't require a counterpart entity to test.

---

## Requirements Analysis

### Functional Requirements
- `ZenohId` wraps a 16-byte identifier with hex formatting, equality, hashCode
- `WhatAmI` enum maps zenoh-c bitmask values (1=router, 2=peer, 4=client)
- `Hello` data class holds zid, whatami, and locators from scouting
- `Session.zid` returns the session's own ZenohId
- `Session.routersZid()` returns connected router ZIDs
- `Session.peersZid()` returns connected peer ZIDs
- `Zenoh.scout()` discovers zenoh entities on the network
- CLI examples mirror zenoh-c flag conventions

### Non-Functional Requirements
- 6 new C shim functions compile without warnings
- No regressions in existing 148 tests
- `fvm dart analyze` clean

---

## Architecture

### C Shim Layer (6 new functions)

```c
FFI_PLUGIN_EXPORT void zd_info_zid(const z_loaned_session_t* session, uint8_t* out_id);
FFI_PLUGIN_EXPORT int zd_info_routers_zid(const z_loaned_session_t* session, uint8_t* out_ids, int max_count);
FFI_PLUGIN_EXPORT int zd_info_peers_zid(const z_loaned_session_t* session, uint8_t* out_ids, int max_count);
FFI_PLUGIN_EXPORT void zd_id_to_string(const uint8_t* id, z_owned_string_t* out);
FFI_PLUGIN_EXPORT int zd_whatami_to_view_string(int whatami, z_view_string_t* out);
FFI_PLUGIN_EXPORT int zd_scout(z_owned_config_t* config, int64_t dart_port, uint64_t timeout_ms, int what);
```

### Dart API Layer (3 new classes + extensions)

- **ZenohId**: Pure Dart value type wrapping 16 bytes. `toHexString()` uses native `zd_id_to_string` for consistent LSB-first formatting.
- **WhatAmI**: Enum with `router`, `peer`, `client`. `fromInt()` maps zenoh-c bitmask values.
- **Hello**: Data class with `zid`, `whatami`, `locators`. Created from scout callback data.
- **Session.zid**: Getter calling `zd_info_zid`.
- **Session.routersZid()**: Buffer-based synchronous collection via `zd_info_routers_zid`.
- **Session.peersZid()**: Buffer-based synchronous collection via `zd_info_peers_zid`.
- **Zenoh.scout()**: Async via NativePort. Posts Hello data per callback, null sentinel on completion.

---

## Key Design Decisions

### 1. Synchronous collection for info ZIDs
The `z_info_routers_zid` and `z_info_peers_zid` zenoh-c functions use closures that fire synchronously during the call. The C shim collects ZIDs into a caller-provided buffer (16 bytes per ZID, max_count entries). This avoids NativePort overhead for a bounded, fast operation.

### 2. NativePort for scout
Scout blocks for `timeout_ms` and produces unbounded results. The C shim posts each Hello as a Dart_CObject array to the NativePort, followed by a null sentinel. This matches the established subscriber callback pattern.

### 3. ZenohId hex via native call
Uses `zd_id_to_string` (wrapping `z_id_to_string`) for consistent LSB-first hex formatting that matches zenoh-c/zenoh-cpp output. Pure Dart hex encoding would risk byte-order mismatches.

### 4. CLI examples in `example/`
Design doc referenced `packages/zenoh/bin/` but project convention (established Phase 1, commit 2cfdc1f) places CLI examples in `packages/zenoh/example/`.

### 5. Config consumption in scout
`z_scout` consumes the config via `z_config_move`. Dart wrapper calls `config.markConsumed()` after the FFI call, matching `Session.open` pattern.

---

## Deferred Features

| Feature | Rationale |
|---------|-----------|
| Whatami bitmask combinations | `what` param accepts raw int; typed enum covers common cases |
| `z_hello_clone`/`z_hello_drop` | Hello data extracted in C callback, Dart receives pure data |
| Scout `what` filter as typed enum | Exposed as raw `int?` for now; typed API in future phase |

---

## Test Port Allocation

| Test Group | Port(s) |
|-----------|---------|
| Session peersZid (Slice 3) | 17460 |
| Scout peer discovery (Slice 4) | 17461 |
| z_scout CLI (Slice 6) | 18561 |

---

## Slice Summary

| Slice | Name | Tests | Depends on | Blocks |
|-------|------|-------|-----------|--------|
| 1 | ZenohId and WhatAmI Value Types | 6 | none | 2, 3, 4, 5, 6 |
| 2 | Session.zid (C shim + Dart) | 4 | 1 | 3, 5, 6 |
| 3 | Session.routersZid and peersZid | 6 | 2 | 5, 6 |
| 4 | Zenoh.scout (C shim + Dart + Hello) | 7 | 1, 2 | 5, 6 |
| 5 | z_info CLI Example | 4 | 2, 3 | 6 |
| 6 | z_scout CLI Example | 4 | 4, 5 | none |
| **Total** | | **31** | | |
