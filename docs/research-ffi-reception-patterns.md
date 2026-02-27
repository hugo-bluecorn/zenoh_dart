# FFI Reception Patterns: NativePort vs. Channels vs. NativeCallable

Deep analysis of how data crosses the native→Dart boundary for zenoh
subscriptions, informed by current Dart 3.11 FFI documentation and isolate
model.

---

## Context

The pattern research (in `dart_zenoh_xplr/docs/zenoh-patterns/`) recommends
FIFO/Ring channels as the primary Dart FFI reception strategy, warning that
callbacks are "difficult." zenoh_dart instead uses a NativePort bridge
(`Dart_PostCObject_DL`). This document examines whether that concern is
valid, outdated, or misframed.

---

## 1. The Three Approaches

### 1A. NativePort Bridge (what zenoh_dart uses today)

```
zenoh-c internal thread                    Dart main isolate
────────────────────                       ──────────────────
zenoh receives message
  → invokes C callback (_zd_sample_callback)
    → extracts keyexpr, payload, kind
    → builds Dart_CObject array
    → Dart_PostCObject_DL(dart_port, &obj)  ──→  ReceivePort listener fires
                                                   → deserialize List
                                                   → Sample object
                                                   → StreamController.add()
                                                   → Stream<Sample>
```

**Mechanism:** The C shim registers a static C function as the zenoh callback.
That function serializes sample data into a `Dart_CObject` (an array of
string + Uint8List + int32) and posts it to a Dart `ReceivePort` via the
Dart Native API DL. The post is thread-safe and non-blocking for the native
caller.

**Per-message cost:**
- C side: extract fields from zenoh sample, build Dart_CObject, memcpy
  payload bytes into the CObject typed data buffer
- VM boundary: Dart VM copies the CObject data into a Dart heap object
- Dart side: receive as `List<dynamic>`, cast fields, construct `Sample`

**No helper isolate needed.** The Dart event loop directly receives messages.

### 1B. FIFO/Ring Channel + Isolate Poll (what dart_zenoh_xplr uses)

```
zenoh-c internal thread                    Helper isolate         Main isolate
────────────────────                       ──────────────         ────────────
zenoh receives message
  → pushes into FIFO channel (C-level)
                                           z_recv() blocks
                                             → wakes up
                                             → extracts payload
                                             → SendPort.send()  ──→  ReceivePort
                                                                      → Stream
```

**Mechanism:** zenoh-c pushes samples into a C-level FIFO channel (an
internal bounded queue). A Dart helper isolate runs a blocking `z_recv()`
loop, pulling samples and forwarding them to the main isolate via
`SendPort.send()`.

**Per-message cost:**
- C side: zenoh pushes sample into FIFO queue (internal copy)
- Helper isolate: blocking FFI call returns, extract payload from C struct,
  convert to Dart types, `SendPort.send()` (Dart-level message copy)
- VM boundary: isolate message passing copies or transfers the object
- Main isolate: receive, construct domain object

**Requires one helper isolate per subscription** (or a multiplexed worker).

### 1C. NativeCallable.listener() (modern Dart 3.1+ API)

```
zenoh-c internal thread                    Dart main isolate
────────────────────                       ──────────────────
zenoh receives message
  → invokes NativeCallable.listener's
    function pointer (from any thread)
    → VM serializes arguments internally
    → posts to creating isolate's event loop  ──→  Dart callback fires
                                                     → arguments deserialized
                                                     → user code executes
```

**Mechanism:** `NativeCallable.listener()` creates a native function pointer
that can be called from any thread. Internally, it uses the same SendPort
mechanism as NativePort — arguments are serialized and posted to the creating
isolate's event loop. The Dart callback fires asynchronously.

**Constraints:**
- **Void return only** — the native caller cannot receive a return value
- Arguments must be FFI-compatible types (primitives, Pointer, Struct)
- The native caller does not block waiting for the Dart callback
- Must call `close()` when done

**This is conceptually identical to the NativePort bridge**, but at a higher
abstraction level — the Dart VM handles the serialization internally instead
of the C shim doing it manually via `Dart_PostCObject_DL`.

---

## 2. Was the Pattern Research Outdated?

**No, not in terms of Dart version.** dart_zenoh_xplr targets Dart ^3.10.7,
zenoh_dart targets ^3.11.0 — essentially the same era.
`NativeCallable.listener()` has been available since Dart 3.1 and was
available to both projects.

**But the research's framing was incomplete.** The pattern research evaluated
three options:
1. Raw C callbacks via `Pointer.fromFunction()` — correctly identified as
   difficult
2. FIFO/Ring channels — correctly identified as excellent for FFI
3. A "Hybrid Approach: FIFO + Isolate" sketch — acknowledged but not explored

What the research missed:
- **`NativeCallable.listener()`** — never mentioned, despite being the
  officially recommended pattern for exactly this use case (native thread →
  Dart notification)
- **`Dart_PostCObject_DL`** — only briefly mentioned, not evaluated as a
  primary strategy
- The distinction between "raw C callback into Dart" (genuinely difficult)
  and "C callback that posts to Dart" (the standard pattern) was blurred

The research correctly identified the *problem* (getting data from native
threads to Dart) but evaluated an incomplete set of *solutions*.

---

## 3. Detailed Comparison

### 3.1 Latency

| Approach | Native→Dart latency | Bottleneck |
|----------|---------------------|------------|
| NativePort bridge | Event loop scheduling | Message posted directly to event queue; fires on next event loop tick |
| FIFO channel + isolate | Polling interval OR blocking wake | Helper isolate must wake from `z_recv()`, then cross isolate boundary |
| NativeCallable.listener | Event loop scheduling | Same mechanism as NativePort (uses SendPort internally) |

**Winner: NativePort / NativeCallable.listener** — one event loop hop vs.
two hops (native→helper isolate→main isolate) for the channel approach.

### 3.2 Per-Message Overhead

| Approach | Copies | Allocations |
|----------|--------|-------------|
| NativePort bridge | 1: payload bytes copied into Dart_CObject, then into Dart heap | Dart_CObject on C stack; Dart List + Uint8List on Dart heap |
| FIFO channel + isolate | 1-2: payload extracted from C sample, possibly copied on SendPort.send() | C sample in FIFO queue; Dart object on helper isolate heap; transfer or copy to main isolate |
| NativeCallable.listener | 1: arguments serialized by VM internally | VM-managed; similar to NativePort |

**Roughly equivalent.** Both approaches copy the payload at least once when
crossing the native→Dart boundary. The channel approach may have an
additional copy at the isolate→isolate boundary (unless using
`TransferableTypedData` for large payloads).

### 3.3 Backpressure

| Approach | Backpressure model |
|----------|--------------------|
| NativePort bridge | **None** — `Dart_PostCObject_DL` always succeeds; messages queue in the ReceivePort's event queue unboundedly |
| FIFO channel | **Implicit** — `z_recv()` blocks the helper isolate; if the helper is busy processing, the FIFO queue absorbs messages (bounded capacity → producer blocks) |
| Ring channel | **None** — oldest samples overwritten when buffer full |
| NativeCallable.listener | **None** — same as NativePort |

**Winner for backpressure: FIFO channel.** The blocking `z_recv()` model
provides natural backpressure — if the Dart side can't keep up, the C-level
queue fills and zenoh's internal thread blocks (with FIFO). NativePort has
no backpressure; a slow Dart consumer accumulates unbounded messages in the
event queue.

**However**, for most zenoh use cases backpressure is handled at the zenoh
protocol level (congestion control drop/block on the publisher side), not
at the subscriber's reception layer. The NativePort's lack of backpressure
is only a problem if Dart processing is significantly slower than message
arrival rate AND the publisher doesn't use congestion control.

### 3.4 Resource Usage

| Approach | Threads | Memory overhead |
|----------|---------|-----------------|
| NativePort bridge | 0 additional Dart threads | One ReceivePort per subscriber |
| FIFO channel + isolate | 1 Dart isolate per subscriber (or multiplexed) | One isolate + its heap + C FIFO buffer |
| NativeCallable.listener | 0 additional Dart threads | One NativeCallable + internal SendPort per subscriber |

**Winner: NativePort / NativeCallable.listener** — no extra isolates.
The channel approach requires at least one worker isolate. While isolates
are lightweight, they're not free — each has its own heap and event loop.

### 3.5 API Ergonomics

| Approach | Dart API surface |
|----------|-----------------|
| NativePort bridge | `ReceivePort.listen()` → transform to `Stream<Sample>` |
| FIFO channel + isolate | `Isolate.spawn()` + `ReceivePort` + worker entry point + shutdown coordination |
| NativeCallable.listener | `NativeCallable.listener(callback)` → pass `.nativeFunction` to C |

**Winner: NativeCallable.listener** — most concise. NativePort is slightly
more verbose (manual `Dart_CObject` construction in C). Channel + isolate
is significantly more boilerplate.

### 3.6 Structured Data Transfer

| Approach | How sample data crosses boundary |
|----------|----------------------------------|
| NativePort bridge | C builds `Dart_CObject` array: `[String, Uint8List, int]` — arrives as `List<dynamic>` in Dart |
| FIFO channel + isolate | C stores in native struct; helper isolate reads fields via FFI, constructs Dart objects, sends via port |
| NativeCallable.listener | Arguments are FFI types (`Pointer<...>`, `Int32`, etc.) — Dart callback receives them directly |

**NativeCallable.listener has a subtlety here:** The arguments are FFI types
that point to native memory. Since the callback is async, the native memory
must remain valid until the Dart callback fires. For zenoh samples, this is
problematic — the `z_loaned_sample_t` is only valid during the C callback
scope. You'd need to **clone the sample** in C before passing the pointer
to the NativeCallable, then free it in the Dart callback. This adds
complexity equivalent to what the NativePort bridge already does (extract
and copy in C).

**NativePort is actually better for structured data** — it handles the
serialization explicitly in C, and Dart receives ready-to-use Dart objects
(`String`, `Uint8List`). No dangling pointer concerns.

---

## 4. What About NativeCallable.listener() for zenoh_dart?

Could zenoh_dart replace its `Dart_PostCObject_DL` bridge with
`NativeCallable.listener()`? Let's evaluate.

### What would change

**Current (NativePort bridge):**
```c
// C shim: _zd_sample_callback (called by zenoh on its thread)
static void _zd_sample_callback(z_loaned_sample_t *sample, void *ctx) {
    zd_subscriber_ctx_t *sub_ctx = (zd_subscriber_ctx_t *)ctx;
    // Extract and serialize into Dart_CObject
    Dart_CObject obj_keyexpr = { .type = Dart_CObject_kString, ... };
    Dart_CObject obj_payload = { .type = Dart_CObject_kTypedData, ... };
    Dart_CObject obj_kind = { .type = Dart_CObject_kInt32, ... };
    Dart_CObject* elements[] = { &obj_keyexpr, &obj_payload, &obj_kind };
    Dart_CObject obj_array = { .type = Dart_CObject_kArray, ... };
    Dart_PostCObject_DL(sub_ctx->dart_port, &obj_array);
}
```

```dart
// Dart: subscriber setup
final receivePort = ReceivePort();
_bindings.zd_declare_subscriber(session, subscriber,
    keyexpr, receivePort.sendPort.nativePort);
receivePort.listen((message) {
  final list = message as List;
  final sample = Sample(
    keyExpr: list[0] as String,
    payload: ZBytes.fromUint8List(list[1] as Uint8List),
    kind: SampleKind.values[list[2] as int],
  );
  _controller.add(sample);
});
```

**Hypothetical (NativeCallable.listener):**
```c
// C shim would need to take a function pointer instead of a port
typedef void (*zd_sample_fn)(const char* keyexpr, uint8_t* payload,
                              int32_t len, int32_t kind);

static void _zd_sample_callback(z_loaned_sample_t *sample, void *ctx) {
    zd_subscriber_ctx_t *sub_ctx = (zd_subscriber_ctx_t *)ctx;
    // Extract fields, COPY payload (sample only valid during callback)
    char* keyexpr_copy = strdup(...);
    uint8_t* payload_copy = malloc(len); memcpy(...);
    // Call the function pointer (NativeCallable)
    sub_ctx->dart_fn(keyexpr_copy, payload_copy, len, kind);
    // PROBLEM: Can't free these yet — Dart callback is async!
}
```

```dart
// Dart: subscriber setup
final callback = NativeCallable<Void Function(
    Pointer<Utf8>, Pointer<Uint8>, Int32, Int32)>.listener(
  (keyexprPtr, payloadPtr, len, kind) {
    final keyexpr = keyexprPtr.toDartString();
    final payload = payloadPtr.asTypedList(len).toList(); // copy
    calloc.free(keyexprPtr);  // free C allocations
    calloc.free(payloadPtr);
    _controller.add(Sample(...));
  },
);
_bindings.zd_declare_subscriber(session, subscriber,
    keyexpr, callback.nativeFunction);
```

### The problem with NativeCallable.listener for this use case

1. **Memory management is harder.** The C shim must allocate copies of the
   keyexpr and payload, and the *Dart* callback must free them. This creates
   a cross-language memory ownership contract that's error-prone. With
   `Dart_PostCObject_DL`, the VM handles the copy — once posted, the C side
   can immediately free or let the stack-allocated `Dart_CObject` go out
   of scope.

2. **No structured data.** `NativeCallable.listener` can only pass FFI
   primitives and pointers. You can't pass a Dart `String` or `Uint8List`
   directly. With `Dart_PostCObject`, you build a rich object (string +
   typed data + int) that arrives as a ready-to-use Dart `List`.

3. **Dart_PostCObject is the lower-level primitive that NativeCallable.listener
   uses internally.** Switching to `NativeCallable.listener` adds a layer
   of abstraction without adding capability — the data still crosses the
   same `SendPort` boundary.

### Verdict

**The current NativePort bridge is the right choice for zenoh_dart.** It's:
- Lower overhead than `NativeCallable.listener` for structured data
- Cleaner memory ownership (C allocates and posts; VM copies; C cleans up)
- The same mechanism that `NativeCallable.listener` uses internally
- Well-established in the Flutter FFI ecosystem

`NativeCallable.listener` would be the right choice if the callback signature
were simple (e.g., a single int notification). For rich structured data
(keyexpr + variable-length payload + metadata), `Dart_PostCObject_DL` is
more direct.

---

## 5. When Channels ARE Better

Despite the NativePort bridge being a good default, zenoh-c's FIFO/Ring
channels have genuine advantages for specific use cases:

### 5.1 Backpressure-sensitive scenarios

If a subscriber cannot keep up with the message rate and you want the
publisher to slow down (via FIFO queue fullness propagating back through
zenoh's internal flow control), the channel approach provides this
naturally. The NativePort bridge has no backpressure — messages queue
unboundedly in the Dart event loop.

**zenoh_dart coverage:** Phase 8 (ChannelQueryable) and Phase 9
(PullSubscriber with Ring channel) provide these alternatives.

### 5.2 Polling / pull-based consumption

Some use cases want to pull the latest sample on demand (e.g., a game loop
reading the latest sensor value at 60fps). The Ring channel's `try_recv()`
is ideal — always get the latest, discard stale data.

**zenoh_dart coverage:** Phase 9 (PullSubscriber) provides exactly this.

### 5.3 Non-blocking query replies

For `z_get()`, you might want to check for replies without blocking. The
FIFO handler's `try_recv()` enables a poll-check-process loop.

**zenoh_dart coverage:** Phase 8 (non_blocking_get) provides this.

---

## 6. Revised Assessment

The pattern research's recommendation was **directionally correct but
imprecise**:

| Research claim | Accuracy | Nuance |
|----------------|----------|--------|
| "Callbacks are difficult for Dart FFI" | **Partially true** | Raw `Pointer.fromFunction()` callbacks are genuinely limited (no closures, same-thread only). But `NativeCallable.listener()` and `Dart_PostCObject_DL` solve the cross-thread problem. The difficulty is specifically with synchronous, return-value callbacks from foreign threads. |
| "FIFO/Ring channels are excellent for Dart FFI" | **True** | They map well to Dart's polling and Stream patterns, especially for backpressure and pull-based consumption. |
| "Channels should be the PRIMARY strategy" | **Debatable** | For the common case (push notifications from zenoh to Dart), NativePort is simpler, lower-latency, and requires fewer resources. Channels are better for specific patterns (pull, backpressure, non-blocking poll). |
| "Hybrid FIFO + Isolate approach" | **Overcomplicated** | NativePort / NativeCallable.listener achieves the same goal without a helper isolate. |

### The real architecture of zenoh_dart

zenoh_dart actually implements **both strategies** across its phases:

- **Phases 2-7, 11-12, 18:** NativePort bridge (push, `Stream<Sample>`)
- **Phase 8:** FIFO channel (pull, `ChannelQueryable.recv()`,
  `ReplyReceiver.tryRecv()`)
- **Phase 9:** Ring channel (pull, `PullSubscriber.tryRecv()`)

This gives users the right tool for each use case, which is exactly what
the pattern research recommends in spirit, even if the specific mechanism
(NativePort vs. isolate) differs from what was proposed.

---

## 7. Future Considerations

### NativeCallable.isolateGroupBound() (Experimental)

This would allow synchronous callbacks with return values from any thread,
running in the isolate group context. If it stabilizes, it could enable
patterns like:

- Queryable handlers that reply synchronously from the zenoh callback
  thread (instead of clone→post→async reply)
- Memory allocation callbacks where zenoh asks Dart for a buffer

**Status:** Experimental in Dart 3.11. Not ready for production use.

### Shared Memory Multithreading (Dart proposal #333)

If Dart adds shared memory between isolates, it could enable:

- Shared ring buffers between a zenoh receiver isolate and the main isolate
  (zero-copy, no message passing)
- Lock-free queues accessible from both native and Dart code

**Status:** Under development, no stable release date announced.

### @Native Annotation + Build Hooks (Dart 3.10+)

The `@Native` annotation with build hooks (`hook/build.dart`) could
simplify zenoh_dart's library loading. Instead of manual
`DynamicLibrary.open()`, the build system would automatically resolve
native symbols.

**Status:** Stable in Dart 3.10, but zenoh_dart's Phase P1 (packaging)
defers `hook/build.dart` to a future phase due to complexity of linking
against an external prebuilt (zenoh-c) rather than compiling a simple C
file.
