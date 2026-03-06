# Audit: zenoh-dart Phases 0-2 (Completed) + Phases 3-5 (Planned) vs zenoh-c/zenoh-cpp

**Date:** 2026-03-06
**Auditor:** CA session
**Commit:** 544fb3f (design docs pushed to main)
**References:** zenoh-c v1.7.2 (`extern/zenoh-c/include/zenoh_commons.h`), zenoh-cpp v1.7.2 (`extern/zenoh-cpp/include/zenoh/api/`)

---

## Part 1: Completed Phases (0-2) vs zenoh-c/zenoh-cpp

### Phase 0 — Bootstrap (27 C shim functions)

| Area | Verdict | Notes |
|------|---------|-------|
| Config lifecycle | **OK** | sizeof/default/insertJson5/loan/drop — matches zenoh-c pattern |
| Session lifecycle | **OK** | sizeof/open/loan/close — z_close + z_session_drop correct |
| KeyExpr | **OK** | View-based (z_view_keyexpr_t), correct for ephemeral use |
| ZBytes | **OK** | copy_from_str/copy_from_buf/to_string/loan/drop complete |
| String utilities | **OK** | owned + view string helpers for FFI string extraction |
| Move semantics | **OK** | All drops use `z_*_move()` before `z_*_drop()` |
| Config consumed by Session | **OK** | markConsumed() prevents double-free |

**Style inconsistency (non-bug):** `zenoh.dart:32` uses `calloc.free(cStr)` for `toNativeUtf8()`-allocated memory. Should be `malloc.free()` for consistency with `config.dart:62-63`. Both work because `package:ffi` delegates to the same system `free()`, but the inconsistency could confuse reviewers.

### Phase 1 — Put/Delete (2 C shim functions)

| Area | Verdict | Notes |
|------|---------|-------|
| zd_put | **OK** | Uses z_put_options_default, passes default opts. Payload consumed via z_bytes_move. |
| zd_delete | **OK** | Uses z_delete_options_default, passes default opts. |
| Dart Session.put | **OK** | _withKeyExpr helper guarantees KeyExpr cleanup |
| Dart Session.putBytes | **OK** | Validates payload state before KeyExpr allocation |
| Dart Session.deleteResource | **OK** | Clean, matches zenoh-cpp `delete_resource` naming |

**Deferred options (correct):** z_put_options_t has encoding, congestion_control, priority, is_express, timestamp, allowed_destination, attachment — all deferred to Phase 3+.

### Phase 2 — Subscriber (3 C shim functions + internal callback)

| Area | Verdict | Notes |
|------|---------|-------|
| NativePort bridge | **OK** | Context struct with Dart_Port, posted via Dart_PostCObject_DL |
| Closure pattern | **OK** | z_closure_sample with _call, _drop, context — correct |
| Error handling | **OK** | Closure manually dropped on failure (not consumed) |
| Context cleanup | **OK** | _zd_sample_drop frees context on subscriber undeclare |
| Dart_CObject format | **OK** | [keyexpr(string), payload(Uint8List), kind(int64), attachment(null\|Uint8List)] |
| StreamController | **OK** | Non-broadcast, single-subscription (fixed in 34c3680) |
| Subscriber.close | **OK** | drop -> receivePort.close -> controller.close -> calloc.free |
| z_subscriber_options_t | **OK** | Only field is `allowed_origin` — we pass NULL (defaults) |

**Known issues (already tracked in MEMORY.md):**

1. **Sample.payload is String** — `utf8.decode(payloadBytes)` fails on binary data. Fix planned: add `payloadBytes: Uint8List` field.
2. **Attachment also string-decoded** — same concern for binary attachments.

**Observation:** The C callback converts payload via `z_bytes_to_string()` then passes as Uint8List. This is a string->bytes->string round-trip. A more efficient approach would pass raw bytes directly from `z_bytes_slice_iter()` or `z_bytes_reader_read()`, but this works correctly for text payloads and the Phase 3 design preserves this approach.

### Overall Phase 0-2 Assessment

**Solid foundation.** The three-layer architecture (C shim -> generated bindings -> Dart API) is clean. Move semantics, cleanup patterns, and error handling all match zenoh-c conventions. The NativePort callback bridge is well-implemented and ready for reuse. The only real gap is the binary payload issue, which is already tracked.

---

## Part 2: Planned Phases (3-5) vs zenoh-c/zenoh-cpp

### Phase 3 — Publisher

#### C shim functions (8 planned) vs zenoh-c API

| Function | zenoh-c equivalent | Verdict |
|----------|-------------------|---------|
| zd_publisher_sizeof | sizeof(z_owned_publisher_t) | **OK** |
| zd_declare_publisher(session, pub, ke, encoding, cc, priority) | z_declare_publisher(session, pub, ke, opts) | **OK** — flattened params with sentinels |
| zd_publisher_loan | z_publisher_loan | **OK** |
| zd_publisher_drop | z_publisher_drop(z_publisher_move()) | **OK** |
| zd_publisher_put(pub, payload, encoding, attachment) | z_publisher_put(pub, payload, opts) | **OK** — flattened, payload+attachment consumed |
| zd_publisher_delete(pub) | z_publisher_delete(pub, opts) | **OK** — timestamp deferred |
| zd_publisher_keyexpr(pub) | z_publisher_keyexpr(pub) | **OK** |
| zd_publisher_declare_background_matching_listener(pub, port) | z_publisher_declare_background_matching_listener(pub, closure) | **OK** — NativePort variant |
| zd_publisher_get_matching_status(pub, matching) | z_publisher_matching_status(pub, status) | **OK** |

#### Deferred options audit (z_publisher_options_t)

| Field | Status | Phase |
|-------|--------|-------|
| encoding | **Included** | Phase 3 |
| congestion_control | **Included** | Phase 3 |
| priority | **Included** | Phase 3 |
| is_express | Deferred | Future |
| reliability | Deferred | Future (unstable) |
| allowed_destination | Deferred | Future |

#### Deferred options audit (z_publisher_put_options_t)

| Field | Status | Phase |
|-------|--------|-------|
| encoding | **Included** (per-put override) | Phase 3 |
| timestamp | Deferred | Future |
| source_info | Deferred | Future (unstable) |
| attachment | **Included** | Phase 3 |

#### Dart API vs zenoh-cpp Publisher

| zenoh-cpp method | Dart equivalent | Verdict |
|-----------------|-----------------|---------|
| put(Bytes&&, PutOptions) | put(value, {encoding, attachment}) + putBytes() | **OK** |
| delete_resource(DeleteOptions) | deleteResource() | **OK** |
| get_keyexpr() | get keyExpr | **OK** |
| undeclare() | close() | **OK** — Dart convention |
| declare_matching_listener | matchingStatus stream | **OK** — NativePort variant |
| get_matching_status() | hasMatchingSubscribers() | **OK** |
| get_id() | Not included | **OK** — unstable API |

**Sample evolution:** Adding `encoding` as 5th Dart_CObject element requires updating both C callback and Dart ReceivePort listener — design accounts for this.

**FINDING [SUGGESTION]:** The design uses `zd_publisher_declare_background_matching_listener` which auto-cleans on publisher drop. This is the simplest approach but means you can't stop the listener independently. zenoh-cpp offers both `declare_matching_listener` (returns handle) and `declare_background_matching_listener` (fire-and-forget). The background variant is sufficient for Phase 3 — a listener handle could be added later if needed.

### Phase 4 — SHM

**Build flags:** Requires `-DZENOHC_BUILD_WITH_SHARED_MEMORY=TRUE -DZENOHC_BUILD_WITH_UNSTABLE_API=TRUE`. Design correctly gates all C shim functions with `#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)`.

**Design is architecturally sound:**
- Hides `z_buf_layout_alloc_result_t` complexity from Dart
- Provides two allocation strategies (fast fail vs gc+defrag+blocking)
- Zero-copy path via `zd_bytes_from_shm_mut`
- Defers receive-side SHM detection to Phase 4.1

**FINDING [SUGGESTION]:** SHM is unstable API in zenoh-c v1.7.2. If the project targets production before zenoh stabilizes SHM, this phase could be deprioritized. But the design is ready whenever it's needed.

### Phase 5 — Scout/Info

#### C shim functions (6 planned) vs zenoh-c API

| Function | Approach | Verdict |
|----------|----------|---------|
| zd_info_zid | Synchronous, writes 16 bytes | **OK** |
| zd_info_routers_zid | Buffer collection, max_count=32 | **OK** — pragmatic limit |
| zd_info_peers_zid | Same as routers | **OK** |
| zd_id_to_string | ZID -> hex string | **OK** |
| zd_whatami_to_view_string | Enum -> human string | **OK** |
| zd_scout | NativePort, blocks for timeout_ms | **OK** |

**FINDING [NOTE]:** `Zenoh.scout()` blocks the calling isolate for `timeout_ms` (default 1000ms). The design returns `Future<List<Hello>>` but the FFI call is synchronous. For production use, callers should run this on a helper isolate. The design acknowledges this trade-off — acceptable for Phase 5, could add an isolate-based wrapper later.

**WhatAmI values:** 1 (router), 2 (peer), 4 (client) — bitmask, not sequential. Design handles this correctly with explicit enum values.

---

## Part 3: Cross-Cutting Patterns Assessment

| Pattern | Verdict | Notes |
|---------|---------|-------|
| Encoding (string-passthrough) | **GOOD** | Pure Dart class, no FFI wrapping. C shim receives const char* |
| QoS enums | **GOOD** | CongestionControl (0-1), Priority (1-7). Matches zenoh-c exactly |
| Flattened params with sentinels | **GOOD** | -1 for default enums, NULL for optional. Clean FFI boundary |
| Entity lifecycle | **GOOD** | declare -> ops -> close. Consistent with Session, Subscriber |
| NativePort callback bridge | **GOOD** | Proven in Phase 2, reusable template |
| Port ranges for tests | **GOOD** | Non-overlapping per phase prevents test interference |

---

## Part 4: zenoh-c/zenoh-cpp Reference Data

### zenoh-c Options Structs (from zenoh_commons.h)

```c
// z_put_options_t
struct z_put_options_t {
  struct z_moved_encoding_t *encoding;
  enum z_congestion_control_t congestion_control;
  enum z_priority_t priority;
  bool is_express;
  struct z_timestamp_t *timestamp;
  enum z_reliability_t reliability;          // unstable
  enum z_locality_t allowed_destination;
  const z_source_info_t *source_info;        // unstable
  struct z_moved_bytes_t *attachment;
};

// z_delete_options_t
struct z_delete_options_t {
  enum z_congestion_control_t congestion_control;
  enum z_priority_t priority;
  bool is_express;
  struct z_timestamp_t *timestamp;
  enum z_reliability_t reliability;          // unstable
  enum z_locality_t allowed_destination;
};

// z_publisher_options_t
struct z_publisher_options_t {
  struct z_moved_encoding_t *encoding;
  enum z_congestion_control_t congestion_control;
  enum z_priority_t priority;
  bool is_express;
  enum z_reliability_t reliability;          // unstable
  enum z_locality_t allowed_destination;
};

// z_publisher_put_options_t
struct z_publisher_put_options_t {
  struct z_moved_encoding_t *encoding;
  const struct z_timestamp_t *timestamp;
  const z_source_info_t *source_info;        // unstable
  struct z_moved_bytes_t *attachment;
};

// z_publisher_delete_options_t
struct z_publisher_delete_options_t {
  const struct z_timestamp_t *timestamp;
};

// z_subscriber_options_t
struct z_subscriber_options_t {
  enum z_locality_t allowed_origin;
};

// z_get_options_t
struct z_get_options_t {
  enum z_query_target_t target;
  struct z_query_consolidation_t consolidation;
  struct z_moved_bytes_t *payload;
  struct z_moved_encoding_t *encoding;
  enum z_congestion_control_t congestion_control;
  bool is_express;
  enum z_locality_t allowed_destination;
  enum zc_reply_keyexpr_t accept_replies;    // unstable
  enum z_priority_t priority;
  const z_source_info_t *source_info;        // unstable
  struct z_moved_bytes_t *attachment;
  uint64_t timeout_ms;
  z_moved_cancellation_token_t *cancellation_token;  // unstable
};

// z_queryable_options_t
struct z_queryable_options_t {
  bool complete;
  enum z_locality_t allowed_origin;
};
```

### zenoh-cpp Sample Fields (from sample.hxx)

```
keyexpr          : const KeyExpr&
payload          : const Bytes& / Bytes&
encoding         : const Encoding&
kind             : SampleKind (PUT, DELETE)
attachment       : optional<const Bytes&>
timestamp        : optional<Timestamp>
priority         : Priority
congestion_control: CongestionControl
express          : bool
source_info      : optional<const SourceInfo&>   // unstable
reliability      : Reliability                    // unstable
```

### zenoh-cpp Session Methods (from session.hxx)

```
open(Config&&, SessionOptions&&)
close(SessionCloseOptions&&)
is_closed()
get_zid()
declare_keyexpr(KeyExpr&)
undeclare_keyexpr(KeyExpr&&)
put(KeyExpr&, Bytes&&, PutOptions&&)
delete_resource(KeyExpr&, DeleteOptions&&)
declare_publisher(KeyExpr&, PublisherOptions&&)
declare_subscriber(KeyExpr&, callback, SubscriberOptions&&)
declare_queryable(KeyExpr&, callback, QueryableOptions&&)
get(KeyExpr&, parameters, callback, GetOptions&&)
declare_querier(KeyExpr&, QuerierOptions&&)
get_routers_z_id()
get_peers_z_id()
liveliness_declare_token(KeyExpr&)
liveliness_declare_subscriber(KeyExpr&, callback)
```

### zenoh-cpp Publisher Methods (from publisher.hxx)

```
put(Bytes&&, PutOptions&&)
delete_resource(DeleteOptions&&)
get_keyexpr()
undeclare()
declare_matching_listener(callback)
declare_background_matching_listener(callback)
get_matching_status()
```

---

## Summary

| Phase | Functions | Verdict | Key Notes |
|-------|-----------|---------|-----------|
| 0 (Bootstrap) | 27 C shim | **PASS** | Clean foundation, all patterns correct |
| 1 (Put/Delete) | 2 C shim | **PASS** | Default options, deferred fields documented |
| 2 (Subscriber) | 3 C shim + callback | **PASS** | NativePort bridge proven, binary payload tracked |
| 3 (Publisher) | 8 planned | **PASS** | Maps exactly to zenoh-c structs, deferred fields documented |
| 4 (SHM) | 12 planned | **PASS** | Correctly gated, architecturally sound |
| 5 (Scout/Info) | 6 planned | **PASS** | Scout blocking trade-off acceptable |

**No blockers for Phase 3 planning.**
