# Synthesis: zenoh-dart Phases vs. Zenoh Communication Patterns

This document correlates the **zenoh-dart implementation phases** (`docs/phases/`)
with the **Zenoh communication pattern research** (`dart_zenoh_xplr/docs/zenoh-patterns/`),
identifying how each phase maps to documented patterns, where coverage gaps exist,
and how the implementation sequence aligns with the recommended Dart FFI strategy.

---

## 1. Pattern-to-Phase Mapping

### 1.1 Reception Patterns (ZENOH_RECEPTION_PATTERNS.md)

The pattern research identified three reception strategies, ranked by Dart FFI
suitability:

| Reception Pattern | Research Rating | Phase(s) | Actual Mechanism in zenoh-dart |
|-------------------|-----------------|----------|--------------------------------|
| **Callback** (push) | Difficult | Phase 2 (Subscriber) | `Dart_PostCObject_DL` bridge — NOT raw `Pointer.fromFunction()` |
| **FIFO Channel** (pull, unbounded) | Excellent | Phase 8 (ChannelQueryable, NonBlockingGet) | Direct C-level FIFO + Dart polling |
| **Ring Channel** (pull, bounded) | Excellent | Phase 9 (PullSubscriber) | Direct C-level Ring + Dart `tryRecv()` |

The pattern research recommends FIFO/Ring channels as the primary strategy and
warns against raw callbacks. zenoh-dart implements callback subscribers *first*
(Phase 2), deferring channels to Phases 8-9. This sequencing is justified —
see Section 5 for the full FFI analysis.

**What the research got right:** Raw `Pointer.fromFunction()` callbacks are
genuinely limited (static functions only, same-thread only, no closures,
pending deprecation). FIFO/Ring channels are excellent for pull-based patterns.

**What the research missed:** It conflated "C callbacks" with "getting data
from native threads into Dart." Modern Dart provides two mechanisms the
research did not evaluate:

1. **`Dart_PostCObject_DL`** (what zenoh-dart uses) — the C callback
   serializes data into a `Dart_CObject` and posts it directly to a Dart
   `ReceivePort`. Thread-safe, non-blocking, no helper isolate needed.
2. **`NativeCallable.listener()`** (Dart 3.1+, never mentioned in research)
   — creates a native function pointer callable from any thread; the VM
   posts arguments to the creating isolate's event loop internally. Uses
   the same SendPort mechanism as `Dart_PostCObject_DL` under the hood.

Both solve the cross-thread problem without channels or helper isolates.

---

### 1.2 Publishing Patterns (ZENOH_PUBLISHING_PATTERNS.md)

| Publishing Pattern | Phase(s) | Coverage |
|--------------------|----------|----------|
| **Direct put** (`z_put`) | Phase 1 | Complete — `Session.put()`, `Session.putBytes()` |
| **Direct delete** (`z_delete`) | Phase 1 | Complete — `Session.delete()` |
| **Declared Publisher** | Phase 3 | Complete — `Publisher` class with `put()`, `putBytes()`, `close()` |
| **Publisher delete** (`z_publisher_delete`) | Phase 3 | Implicit via Publisher lifecycle |
| **Publisher matching listener** | Phase 3 | Complete — `matchingStatus` stream on Publisher |
| **Encoding options** | Phase 3 | Partial — textPlain, applicationOctetStream, applicationJson only |
| **Congestion control** | Phase 14 | Complete — `CongestionControl.drop`, `.block` |
| **Priority levels** | Phase 14 | Complete — all 7 levels (realTime → background) |
| **Express mode** (`is_express`) | Phase 12 | Complete — `isExpress` parameter on `declarePublisher()` |
| **Attachments** (out-of-band metadata) | Not explicitly phased | Gap — mentioned in pattern doc but no phase adds attachment support to publishers |
| **Timestamps** (HLC) | Phase 18 (prereq) | Partial — config-level timestamp enablement, not per-message API |
| **Reliability** (unstable) | Not phased | Intentional omission — unstable API |
| **Locality** (`allowed_destination`) | Not phased | Gap — not covered in any phase |
| **SHM publishing** | Phase 4 | Complete — ShmProvider, ShmMutBuffer, zero-copy path |
| **Advanced Publisher** (cache, detection) | Phase 18 | Complete — AdvancedPublisher with cache, heartbeat, miss detection |

**Coverage assessment:** Publishing patterns are well-covered across phases.
The primary gaps are **attachments** and **locality** — both are less common
use cases. Attachments appear in Sample (Phase 2) but not in the put/publisher
API. The pattern doc's encoding list is extensive (JSON, XML, protobuf, CBOR,
CDR, etc.) while zenoh-dart starts with just three encodings in Phase 3.

---

### 1.3 Queryable Patterns (ZENOH_QUERYABLE_PATTERNS.md)

| Queryable Pattern | Phase(s) | Coverage |
|-------------------|----------|----------|
| **Callback Queryable** | Phase 6 | Complete — `Queryable` with `Stream<Query>` (via NativePort) |
| **Channel Queryable** (FIFO) | Phase 8 | Complete — `ChannelQueryable` with `recv()` polling |
| **z_get** (one-shot query) | Phase 6 | Complete — `Session.get()` returning `Stream<Reply>` |
| **Non-blocking get** (try_recv) | Phase 8 | Complete — `ReplyReceiver` with `tryRecv()` |
| **Declared Querier** | Phase 10 | Complete — `Querier` with periodic `get()` and matching listener |
| **Query with payload** | Phase 7 | Complete — `Session.get()` accepts `ZBytes? payload` |
| **Query cloning** (async processing) | Phase 6 | Complete — C shim clones query for Dart-side async reply |
| **Error replies** (`z_query_reply_err`) | Not phased | Gap — Phase 6 defines `Reply.error` for reading errors but not for *sending* error replies from queryables |
| **Delete replies** (`z_query_reply_del`) | Not phased | Gap — not covered |
| **Query target modes** | Phase 6 | Complete — `QueryTarget` enum (bestMatching, all, allComplete) |
| **Consolidation modes** | Not phased | Gap — AUTO/NONE/MONOTONIC/LATEST not exposed |
| **Queryable `complete` flag** | Phase 6 | Complete — `declareQueryable(keyExpr, {complete?})` |
| **SHM query/reply** | Phase 7 | Complete — both SHM request and response payloads |
| **Querier matching** | Phase 10 | Complete — `matchingStatus` stream on Querier |

**Coverage assessment:** Core query/reply is thoroughly covered. The gaps are
in advanced reply types (error replies, delete replies) and consolidation modes
— features that are less commonly needed in practice.

---

### 1.4 Liveliness Patterns (ZENOH_LIVELINESS_PATTERNS.md)

| Liveliness Pattern | Phase(s) | Coverage |
|--------------------|----------|----------|
| **Token declaration** | Phase 11 | Complete — `LivelinessToken` with `close()` |
| **Liveliness subscriber** | Phase 11 | Complete — reuses `Subscriber` class (PUT=alive, DELETE=dead) |
| **Liveliness subscriber with history** | Phase 11 | Complete — `history` option on subscriber |
| **Liveliness get** (snapshot query) | Phase 11 | Complete — `liveliness.get()` returning `Stream<Reply>` |
| **Background liveliness subscriber** | Not explicitly phased | Gap — fire-and-forget variant not mentioned |

**Coverage assessment:** Excellent. Phase 11 maps almost 1:1 to the liveliness
pattern document. The pattern doc's use case examples (health check, device
discovery, service registration) are all achievable with the Phase 11 API.

---

### 1.5 Advanced Subscriber Patterns (ZENOH_ADVANCED_SUBSCRIBER_PATTERNS.md)

| Advanced Subscriber Feature | Phase(s) | Coverage |
|-----------------------------|----------|----------|
| **History recovery** (late joiner) | Phase 18 | Complete — `AdvancedSubscriberOptions.history` |
| **Late publisher detection** | Phase 18 | Complete — `detectLatePublishers` option |
| **Sample miss detection** | Phase 18 | Complete — `MissEvent` stream with sourceId + count |
| **Recovery** (retransmission) | Phase 18 | Complete — `recovery` option |
| **Heartbeat mode** | Phase 18 (via publisher) | Complete — Advanced publisher heartbeat config |
| **Periodic query mode** | Phase 18 | Implied via options |
| **Querying Subscriber** (deprecated) | Not phased | Correct omission — deprecated API |

**Coverage assessment:** Complete. Phase 18 implements the full advanced
subscriber contract as described in the pattern doc, including the
publisher↔subscriber feature matrix (cache ↔ history, heartbeat ↔ miss
detection).

---

### 1.6 Discovery Patterns (ZENOH_DISCOVERY_PATTERNS.md)

| Discovery Pattern | Phase(s) | Coverage |
|-------------------|----------|----------|
| **Scouting** (pre-session) | Phase 5 | Complete — `scout()` returning `Stream<Hello>` |
| **Session info** (ZID) | Phase 5 | Complete — `Session.zid`, `routersZid()`, `peersZid()` |
| **Publisher matching** | Phase 3 | Complete — `Publisher.matchingStatus` |
| **Querier matching** | Phase 10 | Complete — `Querier.matchingStatus` |
| **WhatAmI filter** for scouting | Phase 5 | Partial — Hello exposes `whatami` string but no filter parameter on `scout()` |

**Coverage assessment:** Excellent. The three-tier discovery model (pre-session
scouting → post-session info → operation-time matching) maps cleanly to
Phases 5, 3, and 10.

---

### 1.7 Additional Patterns (ZENOH_ADDITIONAL_PATTERNS.md)

| Additional Pattern | Phase(s) | Coverage |
|--------------------|----------|----------|
| **Storage** (sub+queryable+map) | Phase 17 | Complete — composite pattern with keyexpr matching |
| **Delete operations** | Phase 1 | Complete |
| **Synchronization** (mutex, condvar) | Not phased | Correct omission — Dart uses `package:synchronized` / isolates |
| **Background entities** | Phase 12 | Partial — `declareBackgroundSubscriber()` for ping/pong only |
| **Ping/Pong latency** | Phase 12 | Complete — z_ping + z_pong |
| **Clock/Sleep utilities** | Not phased | Correct omission — use Dart's `Stopwatch` / `Future.delayed()` |
| **Key expression utilities** | Phase 17 | Complete — `KeyExpr.intersects()`, `KeyExpr.includes()` |
| **Bytes/Encoding** | Phase 16 | Comprehensive — full serialization/deserialization API |
| **Error codes** | Phase 0 | Complete — `ZenohException` wraps return codes |

**Coverage assessment:** Strong. The pattern doc explicitly recommends against
FFI-wrapping sync primitives and clock utilities for Dart, and zenoh-dart
correctly follows this advice.

---

## 2. Phase Sequence vs. Pattern Priority Tiers

The pattern research defines three implementation priority tiers. Here's how
the zenoh-dart phase sequence aligns:

### Tier 1 (Must Implement) — Pattern Research Recommendation

| Pattern Doc Tier 1 | zenoh-dart Phase | Sequence Position |
|--------------------|------------------|-------------------|
| FIFO/Ring subscribers | Phase 8, 9 | Mid-sequence |
| Publisher (`z_declare_publisher`) | Phase 3 | Early |
| `z_put` (direct publish) | Phase 1 | Very early |
| Channel Queryable | Phase 8 | Mid-sequence |
| `z_get` (one-shot query) | Phase 6 | Mid-sequence |

### Tier 2 (Should Implement)

| Pattern Doc Tier 2 | zenoh-dart Phase | Sequence Position |
|--------------------|------------------|-------------------|
| Liveliness tokens | Phase 11 | Late-mid |
| Matching listeners | Phase 3, 10 | Early + late-mid |
| Querier | Phase 10 | Late-mid |

### Tier 3 (Advanced/Future)

| Pattern Doc Tier 3 | zenoh-dart Phase | Sequence Position |
|--------------------|------------------|-------------------|
| Advanced subscriber/publisher | Phase 18 | Final |
| SHM | Phase 4, 7, 13, 15 | Interspersed |
| Scouting | Phase 5 | Mid-sequence |

**Analysis:** The zenoh-dart phase sequence diverges from the pattern research's
tier ordering in two notable ways:

1. **SHM is early (Phase 4)** in zenoh-dart but Tier 3 in pattern research.
   This is because zenoh-dart's phases are organized around the *zenoh-c
   example programs* (z_pub_shm, z_sub_shm, etc.) rather than by pattern
   complexity. SHM pub/sub naturally follows regular pub/sub.

2. **Channel patterns are mid-sequence (Phase 8-9)** despite being Tier 1 in
   pattern research. This is because zenoh-dart's NativePort bridge pattern
   effectively provides channel-like semantics from Phase 2 onward, making
   explicit FIFO/Ring channels supplementary rather than foundational.

---

## 3. Cross-Reference: CLI Examples to Patterns

Each zenoh-dart CLI example maps to one or more documented patterns:

| CLI Example | Phase | Primary Pattern | Secondary Patterns |
|-------------|-------|-----------------|-------------------|
| `z_put` | 1 | Direct Put | — |
| `z_delete` | 1 | Delete Operation | — |
| `z_sub` | 2 | Callback Subscriber | Reception (callback→NativePort) |
| `z_pub` | 3 | Declared Publisher | Matching Listener |
| `z_pub_shm` | 4 | SHM Publishing | Declared Publisher |
| `z_sub_shm` | 4 | SHM Reception | Callback Subscriber |
| `z_scout` | 5 | Scouting (pre-session) | — |
| `z_info` | 5 | Session Info | — |
| `z_get` | 6 | One-shot Query | FIFO reply reception |
| `z_queryable` | 6 | Callback Queryable | Query cloning |
| `z_get_shm` | 7 | SHM Query | Query with payload |
| `z_queryable_shm` | 7 | SHM Reply | — |
| `z_queryable_with_channels` | 8 | Channel Queryable (FIFO) | Polling reception |
| `z_non_blocking_get` | 8 | Non-blocking Reply | Ring/FIFO try_recv |
| `z_pull` | 9 | Ring Channel Subscriber | Pull-based reception |
| `z_querier` | 10 | Declared Querier | Matching Listener |
| `z_liveliness` | 11 | Liveliness Token | Presence pattern |
| `z_sub_liveliness` | 11 | Liveliness Subscriber | Token monitoring |
| `z_get_liveliness` | 11 | Liveliness Query | Snapshot query |
| `z_pong` | 12 | Background Subscriber | Echo/relay pattern |
| `z_ping` | 12 | Latency Measurement | Express publisher, condvar sync |
| `z_ping_shm` | 13 | SHM Latency | SHM + Ping/Pong |
| `z_pub_thr` | 14 | Throughput Publisher | Congestion control, priority |
| `z_sub_thr` | 14 | Throughput Subscriber | Background subscriber |
| `z_pub_shm_thr` | 15 | SHM Throughput | SHM + throughput |
| `z_bytes` | 16 | Bytes Serialization | Encoding API |
| `z_storage` | 17 | Storage (composite) | Sub + Queryable + keyexpr matching |
| `z_advanced_pub` | 18 | Advanced Publisher | Cache, detection, heartbeat |
| `z_advanced_sub` | 18 | Advanced Subscriber | History, recovery, miss detection |

**Total: 29 CLI examples across 18 phases + 1 packaging phase.**

---

## 4. Coverage Gaps Analysis

### 4.1 Patterns Documented but Not Implemented

| Pattern | Source Doc | Risk | Notes |
|---------|-----------|------|-------|
| **Attachments on put/publish** | Publishing Patterns | Low | Sample *reads* attachments (Phase 2), but no phase adds attachment *writing* to `Session.put()` or `Publisher.put()` |
| **Consolidation modes** | Queryable Patterns | Low | AUTO/NONE/MONOTONIC/LATEST for deduplicating query replies — useful for multi-queryable scenarios |
| **Error replies** from queryable | Queryable Patterns | Low | `z_query_reply_err()` — queryable can send structured errors back to querier |
| **Delete replies** from queryable | Queryable Patterns | Low | `z_query_reply_del()` — queryable replies with deletion notification |
| **Locality** (`allowed_destination`) | Publishing Patterns | Low | Restrict put/publish to local or remote subscribers only |
| **Full encoding set** | Publishing Patterns | Low | Only 3 encodings in Phase 3; pattern doc lists ~15 standard encodings |
| **Background queryable** | Additional Patterns | Low | Fire-and-forget queryable (no handle management) |
| **WhatAmI filter on scout** | Discovery Patterns | Low | Filter scouting by entity type (router/peer/client) |
| **Reliability** (unstable) | Publishing Patterns | None | Intentionally omitted — unstable zenoh-c API |
| **Source info** on put | Publishing Patterns | None | Advanced provenance tracking |

### 4.2 Phases Without Direct Pattern Correspondence

| Phase | Why No Direct Pattern Match |
|-------|---------------------------|
| Phase 0 (Bootstrap) | Infrastructure — Config, Session, KeyExpr, ZBytes are prerequisites, not patterns |
| Phase P1 (Packaging) | Build system — CMake, jniLibs, bundled_libraries are distribution concerns |
| Phase 13 (SHM Ping) | Composition — combines SHM (Phase 4) + Ping/Pong (Phase 12), no new pattern |
| Phase 15 (SHM Throughput) | Composition — combines SHM (Phase 4) + Throughput (Phase 14), no new pattern |

---

## 5. FFI Reception Architecture (Deep Analysis)

This section integrates findings from Dart 3.11 FFI documentation, the
`dart:isolate` concurrency model, and a side-by-side comparison of the
dart_zenoh_xplr (research) and zenoh_dart (production) codebases.

### 5.1 The Four Mechanisms for Native→Dart Data Transfer

Dart 3.11 provides four ways to get data from a native thread into Dart.
The pattern research evaluated only options 1 and 4. Options 2 and 3 —
which zenoh_dart uses or could use — were not analyzed.

| # | Mechanism | How it works | Thread safety |
|---|-----------|--------------|---------------|
| 1 | `Pointer.fromFunction()` | Static C function pointer, invoked synchronously | Same thread only — **aborts if called from foreign thread** |
| 2 | `Dart_PostCObject_DL` | C code posts a `Dart_CObject` to a Dart `ReceivePort` via native port ID | **Any thread** — thread-safe, non-blocking |
| 3 | `NativeCallable.listener()` | Dart 3.1+ API; creates native function pointer callable from any thread; VM posts arguments to creating isolate's event loop via internal SendPort | **Any thread** — void return only |
| 4 | FIFO/Ring channel + isolate poll | C-level queue; Dart helper isolate calls blocking `z_recv()` then forwards via `SendPort.send()` | Thread-safe (queue is internal to zenoh-c) |

Additionally, `NativeCallable.isolateLocal()` (Dart 3.2+) supports closures
and return values but is **same-thread only** (aborts from foreign threads).
`NativeCallable.isolateGroupBound()` is experimental and supports any-thread
with return values, but cannot access isolate-local state.

### 5.2 How Each Project Implements Reception

#### dart_zenoh_xplr (pattern research project): Channel + Isolate Poll

```
zenoh-c thread               Dart helper isolate        Dart main isolate
──────────────               ───────────────────        ─────────────────
message arrives
  → pushed into FIFO
    (C-level queue)
                              z_recv() blocks, wakes
                                → extract payload
                                → SendPort.send() ──────→ ReceivePort
                                                           → Stream
```

- C shim uses global state (`static z_owned_subscriber_t g_subscriber`)
- Exposes blocking `zenoh_recv()` and non-blocking `zenoh_try_recv()`
- **No** `Dart_InitializeApiDL`, no `Dart_PostCObject`, no NativeCallable
- Dart spawns a helper `Isolate` per subscription type
- One extra thread per subscription; two isolate boundary crossings per message

#### zenoh_dart (production): NativePort Bridge

```
zenoh-c thread                                   Dart main isolate
──────────────                                   ─────────────────
message arrives
  → C callback (_zd_sample_callback)
    → extract keyexpr, payload, kind
    → build Dart_CObject array
    → Dart_PostCObject_DL(port, &obj) ──────────→ ReceivePort listener
                                                    → List<dynamic>
                                                    → Sample
                                                    → StreamController
                                                    → Stream<Sample>
```

- C shim uses per-subscriber context (no globals), stateless design
- Calls `Dart_InitializeApiDL()` at startup
- Posts structured `Dart_CObject` (string + Uint8List + int32) per message
- **No helper isolate** — Dart event loop receives directly
- Zero extra threads; one boundary crossing per message

### 5.3 Why NativePort Beats Channels for Push Reception

| Dimension | NativePort bridge | Channel + isolate poll |
|-----------|-------------------|------------------------|
| **Latency** | 1 hop (native → event loop) | 2 hops (native → helper isolate → main isolate) |
| **Resource usage** | 0 extra Dart threads/isolates | 1 isolate per subscription (or multiplexed worker) |
| **Data richness** | Structured `Dart_CObject` arrives as `List<dynamic>` with String, Uint8List, int — ready to use | Helper isolate must read C struct fields via FFI, construct Dart objects, then send across isolate boundary |
| **Memory ownership** | Clean: C builds CObject on stack, VM copies into Dart heap, C stack frame unwinds | Complex: payload in FIFO queue → copied by helper → possibly copied again at isolate boundary |
| **Scalability** | Unlimited concurrent subscribers (each gets own port) | dart_zenoh_xplr hardcodes 2 subscriptions (one int, one string) |
| **Code complexity** | Moderate — manual `Dart_CObject` construction in C | Higher — isolate lifecycle, port wiring, worker entry point, shutdown coordination |

### 5.4 Why Not NativeCallable.listener() Instead?

`NativeCallable.listener()` (Dart 3.1+) is the officially recommended API for
native-thread-to-Dart notifications. Could zenoh_dart use it instead of
`Dart_PostCObject_DL`?

**The answer is: `Dart_PostCObject_DL` is better for this specific use case.**

With `NativeCallable.listener()`, the C shim would need to:
1. Receive the zenoh sample (valid only during the C callback scope)
2. `malloc` copies of the keyexpr string and payload bytes
3. Call the NativeCallable function pointer with raw `Pointer` arguments
4. The Dart callback fires *later* (async) — must free the malloc'd memory

With `Dart_PostCObject_DL`, the C shim:
1. Receives the zenoh sample
2. Builds a stack-allocated `Dart_CObject` referencing the sample's data
3. Posts it — the VM copies the data into the Dart heap during the post
4. The C callback returns — stack frame (and `Dart_CObject`) cleaned up

The key difference: **`Dart_PostCObject_DL` handles the copy atomically
during the post call**, so the C side never needs to `malloc` temporary
buffers or worry about Dart freeing them later. `NativeCallable.listener`
would create a cross-language malloc/free ownership contract that's
error-prone.

Additionally, `NativeCallable.listener` only passes FFI-compatible types
(primitives and `Pointer`). `Dart_PostCObject_DL` can pass strings, typed
data arrays, and nested arrays that arrive as native Dart objects — no
additional deserialization needed.

`NativeCallable.listener` uses the same `SendPort` mechanism internally, so
there is no performance advantage to switching.

### 5.5 Where Channels Genuinely Win

Despite the NativePort bridge being the right default, zenoh-c's FIFO/Ring
channels have genuine advantages for specific use cases that zenoh-dart
correctly implements in Phases 8-9:

**Backpressure (FIFO):** `Dart_PostCObject_DL` always succeeds — messages
queue unboundedly in the Dart event loop. A slow Dart consumer accumulates
memory without limit. FIFO channels provide natural backpressure: when the
queue fills, zenoh's internal thread blocks until the consumer catches up.

- For most zenoh use cases, backpressure is handled at the protocol level
  (publisher congestion control drop/block), not the subscriber's reception
  layer. But for local high-throughput scenarios, FIFO backpressure matters.

**Pull-based consumption (Ring):** Some use cases want to poll the latest
sample on demand — a game loop reading sensor data at 60fps, an animation
frame grabbing the latest camera image. The Ring channel's `try_recv()`
always returns the latest sample, discarding stale data automatically.

**Non-blocking reply polling:** For `z_get()`, checking for replies without
blocking. The FIFO handler's `try_recv()` enables a poll-check-process loop.

### 5.6 The Dual Strategy

zenoh_dart implements **both** reception strategies across its phases:

| Strategy | Mechanism | Phases | Best for |
|----------|-----------|--------|----------|
| **Push** (NativePort) | `Dart_PostCObject_DL` → `ReceivePort` → `Stream` | 2-7, 11-12, 18 | Event-driven consumption, low latency, simple API |
| **Pull** (C channels) | FIFO/Ring `recv()`/`try_recv()` from Dart | 8-9 | Backpressure, polling, "latest value" patterns |

This gives users the right tool for each use case — exactly what the pattern
research recommends in spirit, even though the specific push mechanism differs
from what was proposed.

### 5.7 Dart FFI API Landscape (Dart 3.11)

For reference, here is the complete callback/interop API surface as of
Dart 3.11, and how each relates to zenoh_dart:

| API | Since | Thread Safety | Return Values | zenoh_dart Usage |
|-----|-------|---------------|---------------|------------------|
| `Pointer.fromFunction()` | Dart 2.6 | Same thread only | Yes | **Not used** — correctly avoided; pending deprecation |
| `Dart_PostCObject_DL` | Dart 2.6 | Any thread | N/A (posts data) | **Primary mechanism** for subscriber/queryable callbacks |
| `NativeCallable.isolateLocal()` | Dart 3.2 | Same thread only | Yes (with `exceptionalReturn`) | Not used — zenoh calls from its own threads |
| `NativeCallable.listener()` | Dart 3.1 | Any thread | Void only | Not used — `Dart_PostCObject_DL` is more suitable for structured data |
| `NativeCallable.isolateGroupBound()` | Experimental | Any thread | Yes | Not used — experimental, cannot access isolate state |
| `NativeFinalizer` + `Finalizable` | Dart 2.17 | Callback runs on arbitrary thread | N/A | Should be adopted for native resource cleanup (see Section 5.8) |
| `@Native` + build hooks | Dart 3.3/3.10 | N/A (symbol binding) | N/A | Deferred to Phase P2+ (requires `hook/build.dart`) |

### 5.8 Memory Management Alignment

The pattern research emphasizes three ownership models:

| Model | Pattern Doc | zenoh-dart Implementation |
|-------|-------------|---------------------------|
| `z_owned_*` | Caller owns, must drop | `dispose()` methods + Dart finalizers |
| `z_loaned_*` | Borrowed, do not drop | Handled internally by C shim (loan → use → return) |
| `z_moved_*` | Ownership transferred | C shim uses `z_move()` internally; Dart side never sees moved types |

zenoh-dart's C shim layer fully encapsulates the zenoh-c ownership model,
exposing only `dispose()` to Dart. This matches the pattern doc's Dart FFI
recommendation for `Finalizable` classes.

**Note on `NativeFinalizer`:** Dart 3.11's `NativeFinalizer` provides stronger
guarantees than `dart:core` `Finalizer` — the native callback is guaranteed
to run at least once before isolate group shutdown. zenoh_dart should adopt
`NativeFinalizer` + `Finalizable` for all types holding native memory
(`Session`, `Subscriber`, `Publisher`, `ZBytes`, etc.) to provide safety-net
cleanup if `dispose()` is not called. The `Finalizable` marker interface also
prevents premature GC of objects while their native pointers are in use.

### 5.9 Thread Safety Alignment

| Component | Pattern Doc | zenoh-dart | Dart 3.11 Mechanism |
|-----------|-------------|------------|---------------------|
| Session | Share across isolates | Single session, shared via FFI | `Pointer` can be sent across isolates via `.address` (int) |
| Publisher | One per isolate | One per declaration (Dart single-threaded) | N/A — Dart's single-threaded isolate model prevents concurrent access |
| Subscriber callbacks | Must be thread-safe | NativePort handles thread crossing | `Dart_PostCObject_DL` is thread-safe by design |
| FIFO/Ring handlers | Thread-safe | Accessed from Dart's event loop | Polling from single Dart thread — no contention |

The Dart single-threaded model (per isolate) simplifies thread safety
considerably. The NativePort bridge is the only cross-thread boundary, and
it's handled by the Dart VM's native port mechanism.

**Isolate sharing caveat:** `Pointer` objects can now be sent across isolate
boundaries (resolved in Dart SDK), but `Finalizable` objects and
`DynamicLibrary` instances cannot. If zenoh_dart ever needs multi-isolate
access to the same session, pointers would need to be shared via integer
addresses with manual lifetime management.

---

## 6. Progression Map

How patterns build on each other through the phase sequence:

```
Phase 0: Bootstrap
  │  Config, Session, KeyExpr, ZBytes, ZenohException
  │
  ├─ Phase 1: Direct Put/Delete
  │    z_put, z_delete
  │    │
  │    ├─ Phase 2: Callback Subscriber [NativePort bridge introduced]
  │    │    Subscriber, Sample, Stream<Sample>
  │    │    │
  │    │    ├─ Phase 3: Declared Publisher
  │    │    │    Publisher, Encoding, matching listener
  │    │    │    │
  │    │    │    ├─ Phase 4: SHM [zero-copy layer]
  │    │    │    │    ShmProvider, ShmMutBuffer, ShmBuffer
  │    │    │    │    │
  │    │    │    │    ├─ Phase 7: SHM Query (composes 4+6)
  │    │    │    │    ├─ Phase 13: SHM Ping (composes 4+12)
  │    │    │    │    └─ Phase 15: SHM Throughput (composes 4+14)
  │    │    │    │
  │    │    │    ├─ Phase 12: Ping/Pong [background subscriber, express]
  │    │    │    │    │
  │    │    │    │    └─ Phase 14: Throughput [congestion, priority]
  │    │    │    │
  │    │    │    └─ Phase 18: Advanced Pub/Sub [cache, recovery, miss]
  │    │    │
  │    │    └─ Phase 9: Pull Subscriber [Ring channel]
  │    │
  │    ├─ Phase 5: Scout & Info
  │    │    ZenohId, Hello, scout(), session info
  │    │
  │    └─ Phase 6: Query/Reply [clone-and-post pattern]
  │         Query, Reply, Queryable, Session.get()
  │         │
  │         ├─ Phase 8: Channel Patterns [FIFO channel]
  │         │    ChannelQueryable, ReplyReceiver, non-blocking
  │         │
  │         ├─ Phase 10: Declared Querier
  │         │    Querier, matching listener
  │         │
  │         └─ Phase 11: Liveliness
  │              LivelinessToken, presence detection
  │
  ├─ Phase 16: Bytes Serialization [standalone, only needs ZBytes]
  │    ZSerializer, ZDeserializer
  │
  ├─ Phase 17: Storage [composite: sub + queryable + keyexpr]
  │    KeyExpr.intersects(), KeyExpr.includes()
  │
  └─ Phase P1: Packaging [build infrastructure]
       CMake, jniLibs, bundled_libraries
```

---

## 7. Summary of Findings

### What zenoh-dart does well

1. **Comprehensive CLI example coverage** — 29 examples covering all major
   zenoh patterns, mirroring the zenoh-c example suite
2. **Correct FFI architecture** — The `Dart_PostCObject_DL` bridge is the
   right choice for structured push data (string + bytes + metadata). It
   avoids the limitations the pattern research correctly identified with
   `Pointer.fromFunction()`, without the overhead of helper isolates that
   the channel+poll approach requires. It uses the same underlying SendPort
   mechanism as the newer `NativeCallable.listener()` API but with better
   support for structured data.
3. **Dual reception strategy** — Push via NativePort (Phases 2-7, 11-12, 18)
   and Pull via FIFO/Ring channels (Phases 8-9) gives users the right tool
   for each use case
4. **Progressive complexity** — phases build incrementally, each adding one
   testable behavior pattern
5. **SHM variants** — four phases (4, 7, 13, 15) methodically add zero-copy
   to each communication pattern
6. **Benchmark coverage** — ping/pong (latency) and throughput phases enable
   performance characterization

### What could be added in future phases

1. **`NativeFinalizer` + `Finalizable` adoption** — All types holding native
   memory should implement `Finalizable` (prevents premature GC) and attach
   a `NativeFinalizer` (safety-net cleanup if `dispose()` is missed). This
   is available since Dart 2.17 and provides stronger guarantees than
   `dart:core` `Finalizer`.
2. **Attachment support on publish** — allow `Session.put()` and
   `Publisher.put()` to carry out-of-band metadata
3. **Consolidation modes on get** — deduplication strategies for multi-queryable
   scenarios
4. **Error/delete replies** — queryables responding with structured errors
5. **Extended encoding set** — beyond the initial three encodings
6. **Scout filtering** — `WhatAmI` filter parameter on `scout()`
7. **`@Native` + build hooks** — Replace manual `DynamicLibrary.open()` with
   Dart 3.10's stable build hooks for automatic native symbol resolution
   (deferred to Phase P2+ due to complexity of linking external prebuilts)

### Pattern research accuracy assessment

| Research claim | Verdict | Detail |
|----------------|---------|--------|
| "Callbacks are difficult for Dart FFI" | **Partially true** | Raw `Pointer.fromFunction()` is genuinely limited. But `Dart_PostCObject_DL` and `NativeCallable.listener()` solve the cross-thread problem without those limitations. The research conflated the mechanism (`Pointer.fromFunction`) with the goal (native→Dart data transfer). |
| "FIFO/Ring channels are excellent" | **True** | They map well to pull-based patterns, backpressure, and "latest value" consumption. |
| "Channels should be the PRIMARY strategy" | **Overstated** | For push-driven reception (the common case), NativePort is simpler, lower-latency, and uses fewer resources. Channels are the right choice specifically for backpressure-sensitive, polling, or "latest value" patterns. |
| "Hybrid FIFO + Isolate approach" | **Overcomplicated** | NativePort achieves the same goal without a helper isolate. The research sketched this but didn't realize `Dart_PostCObject_DL` already implements it at a lower level. |
| `NativeCallable.listener()` recommendation | **Not evaluated** | The research never mentions this Dart 3.1+ API, despite it being the officially recommended mechanism for the exact use case (native thread → Dart notification). |
| Both projects use recent Dart | **Confirmed** | dart_zenoh_xplr targets ^3.10.7, zenoh_dart targets ^3.11.0. The research's conclusions were not outdated by Dart version — they were incomplete in API coverage. |

### Key architectural insight

The pattern research and zenoh-dart phases are **complementary perspectives**
on the same API surface. The pattern research is organized by *communication
topology* (pub/sub, request/response, presence), while zenoh-dart phases are
organized by *zenoh-c example programs* (z_put, z_sub, z_pub, etc.). Both
arrive at the same API surface, but the phase structure provides a more
natural TDD decomposition because each example is independently testable.

### Dart FFI evolution to watch

- **`NativeCallable.isolateGroupBound()`** — If this stabilizes, it would
  enable synchronous callbacks with return values from any thread (e.g.,
  queryable handlers replying inline instead of clone→post→async reply).
  Currently experimental.
- **Shared Memory Multithreading (proposal #333)** — Would enable shared
  ring buffers between native and Dart code, lock-free queues, and
  `dart:concurrent` atomics. Under development, no stable release date.
- **`@Native` + build hooks** — Stable in Dart 3.10. Would simplify
  zenoh_dart's library loading if adopted in Phase P2+.
