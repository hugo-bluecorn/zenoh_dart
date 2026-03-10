# Feature Notes: Phase 4 -- SHM Provider + Pub/Sub (Core SHM)

**Created:** 2026-03-06
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Introduce shared memory (SHM) provider infrastructure and SHM-based publishing. SHM buffers enable zero-copy data transfer by allocating payloads in shared memory regions that zenoh passes between peers without copying. This is the primary reason for building dart:ffi bindings rather than using a higher-level approach.

### Use Cases
- High-throughput pub/sub on the same machine without data copying
- IoT edge devices sharing sensor data between co-located processes
- Real-time data pipelines where latency matters
- Counter app using SHM for efficient local data sharing

### Context
Phases 0-3 established the foundation: Session open/close, KeyExpr validation, ZBytes payload, one-shot put/delete, callback-based subscriber via NativePort bridge, and declared publisher with QoS options. Phase 4 adds SHM as a first-class feature, enabling zero-copy publish via ShmProvider and ShmMutBuffer.

---

## Requirements Analysis

### Functional Requirements
- zenoh-c rebuilt with SHM + unstable API flags
- `src/CMakeLists.txt` adds `-DZ_FEATURE_SHARED_MEMORY -DZ_FEATURE_UNSTABLE_API` compile definitions
- 12 C shim functions with `#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)` guards
- `ShmProvider` Dart class: create with named `size` param, alloc, allocGcDefragBlocking, available, close
- `ShmMutBuffer` Dart class: `Pointer<Uint8> get data`, `int get length`, `ZBytes toBytes()`, `void dispose()`
- CLI example `z_pub_shm.dart` mirroring z_pub_shm.c

### Non-Functional Requirements
- No regressions in existing 120 tests
- `fvm dart analyze` clean
- ffigen.yaml updated with SHM opaque type mappings

---

## Architecture

### C Shim Layer (12 new functions)

All guarded with `#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)`:

**SHM Provider Lifecycle (5):** zd_shm_provider_sizeof, zd_shm_provider_new, zd_shm_provider_loan, zd_shm_provider_drop, zd_shm_provider_available

**SHM Allocation (3):** zd_shm_mut_sizeof, zd_shm_provider_alloc, zd_shm_provider_alloc_gc_defrag_blocking

**SHM Mutable Buffer (4):** zd_shm_mut_loan_mut, zd_shm_mut_data_mut, zd_shm_mut_len, zd_bytes_from_shm_mut, zd_shm_mut_drop

### Key Design Decisions

1. **Zero-copy API**: `ShmMutBuffer.data` exposes raw `Pointer<Uint8>` for direct writes. No `setData()` wrapper that would defeat zero-copy purpose.

2. **Named constructor**: `ShmProvider({required int size})` per design doc convention.

3. **Nullable alloc**: `alloc()` and `allocGcDefragBlocking()` return `ShmMutBuffer?` — null on allocation failure rather than throwing.

4. **C shim drop/move pattern**: Drop functions accept `z_owned_*` but internally cast to `z_moved_*` via `(z_moved_shm_provider_t*)(provider)` since move functions aren't in pre-generated headers.

5. **Alloc result hidden from Dart**: `z_buf_layout_alloc_result_t` is handled entirely within the C shim; Dart only sees return codes (0=OK, 1=alloc_error, 2=layout_error).

6. **CMake compile definitions required**: `src/CMakeLists.txt` MUST define `Z_FEATURE_SHARED_MEMORY` and `Z_FEATURE_UNSTABLE_API` for the `#if defined(...)` guards to compile in SHM functions.

---

## Slice Decomposition

| Slice | Name | Tests | Depends | Blocks |
|-------|------|-------|---------|--------|
| 1 | ShmProvider Lifecycle | 7 | none | 2,3,4,5 |
| 2 | ShmMutBuffer Allocation and Properties | 8 | 1 | 3,4,5 |
| 3 | ShmMutBuffer Data Pointer and toBytes | 6 | 2 | 4,5 |
| 4 | SHM Pub/Sub Integration | 4 | 3 | 5 |
| 5 | CLI Example z_pub_shm.dart | 4 | 4 | none |
| **Total** | | **29** | | |

Slice 1 includes all setup: zenoh-c rebuild, CMake definitions, C shim declarations, ffigen.yaml update, bindings regeneration, barrel exports, and library rebuild.

---

## Deferred Features (Phase 4.1+)

- Immutable SHM buffer (`z_owned_shm_t`)
- SHM detection on receive side
- Aligned allocation variants
- SHM client storage
- Shared SHM provider (thread-safe)
- Precomputed layout
- Async defrag allocation

---

## Test Port Allocation

| Test Group | Port(s) |
|-----------|---------|
| SHM Pub/Sub Integration (Slice 4) | 17456 |

---

## References

- Design spec: `docs/design/phase-04-shm-revised.md`
- Cross-cutting patterns: `docs/design/cross-cutting-patterns.md`
- zenoh-c SHM example: `extern/zenoh-c/examples/z_pub_shm.c`
- zenoh-c SHM headers: search for `z_shm_provider`, `z_owned_shm_mut_t` in `extern/zenoh-c/include/`
