# zenoh-dart Examples

> **Audience:** Auditors, new developers, and zenoh users familiar with the
> C or C++ bindings who want to understand what zenoh-dart implements, what
> it skips, and why.
>
> **Convention:** Each example entry below mirrors a zenoh-c example
> (`extern/zenoh-c/examples/z_*.c`). Entries are grouped by zenoh pattern.
> Canon-following examples get brief entries; examples that deviate from
> zenoh-c/zenoh-cpp get expanded architectural rationale.

## How This Binding Maps to zenoh-c

zenoh-dart is a pure Dart FFI package. Dart never calls zenoh-c directly.
All calls pass through a C shim layer (`src/zenoh_dart.c`) whose symbols
use the `zd_` prefix:

```
Dart API  -->  libzenoh_dart.so (C shim, zd_* functions)
                     |
                     +--> libzenohc.so (zenoh-c, z_* functions)
                          resolved by OS linker via DT_NEEDED
```

The C shim exists because six categories of zenoh-c construct cannot cross
the Dart FFI boundary:

| # | Barrier | Example |
|---|---------|---------|
| 1 | `static inline` move functions | `z_move(x)` has no exported symbol |
| 2 | C11 `_Generic` polymorphic macros | `z_drop`, `z_loan`, `z_try_recv` |
| 3 | Options struct initialization | `z_put_options_default()` is a macro |
| 4 | Opaque type sizes | Dart FFI has no `sizeof` for foreign types |
| 5 | Closure callbacks across threads | NativePort bridge for Dart event loop |
| 6 | Loaning and const/mut enforcement | `z_loan()` is macro/inline; Dart erases const |

Every `zd_*` function wraps one or more of these barriers. There are no
unnecessary proxies.

**Dual-reference strategy:** We use zenoh-c as the contract boundary
(correct FFI) and zenoh-cpp as the structural peer (API design). We do
not reference the Rust source — it is one layer too deep.

**Example-driven development:** Each CLI example mirrors its zenoh-c
counterpart — same flags, same defaults, same output format. This ensures
cross-language interop (a Dart `z_get` can query a C `z_queryable`) and
zero cognitive overhead for zenoh users switching languages.

---

## Absent Examples

These zenoh-c examples are intentionally not implemented. Each omission
has a structural reason.

### z_queryable_with_channels / z_non_blocking_get — Dart Streams Replace C Channels

The channel abstraction in zenoh-c (`z_recv`, `z_try_recv` with FIFO
handlers) exists because C has no async runtime. Dart has `Stream`,
`Future`, and `async`/`await`. The existing `z_queryable.dart` and
`z_get.dart` already provide the Dart-idiomatic equivalent:

| zenoh-c Channel Example | C Pattern | zenoh-dart Equivalent | Dart Pattern |
|---|---|---|---|
| `z_queryable_with_channels.c` | `while(1) z_recv()` blocking | `z_queryable.dart` | `await for (q in queryable.stream)` |
| `z_non_blocking_get.c` | `while(1) z_try_recv(); sleep()` | `z_get.dart` | `await for (r in session.get(...))` |

Implementing these would require 11 C shim functions, of which 9 would be
pure facades wrapping exported zenoh-c functions with no FFI barrier.
Blocking `z_recv()` would freeze Dart's single-threaded isolate; polling
`z_try_recv()` with sleep is an anti-pattern when event-driven Streams
exist.

### z_sub_shm — Subscriber Is SHM-Transparent

zenoh-c's `z_sub_shm.c` demonstrates a subscriber that detects and
handles SHM-backed payloads explicitly. In zenoh-dart, all subscribers
already receive SHM-backed data transparently — `Sample.payloadBytes`
returns the bytes regardless of backing. The `ZBytes.isShmBacked` property
lets callers detect SHM when needed, but no separate subscriber example
is required.

### z_bytes — Serialization Utility Demo

zenoh-c's `z_bytes.c` demonstrates custom struct serialization into
`z_owned_bytes_t`. This is a codec tutorial, not a networking pattern.
Dart developers use `dart:convert` for serialization. The `ZBytes` class
provides `fromString()`, `fromUint8List()`, `toBytes()`, and `clone()` —
sufficient for all payload operations.

### z_advanced_pub / z_advanced_sub — Advanced Publication (Future)

These use zenoh-c's advanced publication API (`ze_declare_advanced_publisher`,
`ze_declare_advanced_subscriber`) with sample miss detection, history, and
recovery. Planned for a future phase when the advanced API surface is
implemented.

### z_pub_thr / z_sub_thr / z_pub_shm_thr — Throughput Benchmarks (Future)

Throughput measurement examples. Planned for a future phase alongside
advanced pub/sub.

### z_storage — In-Memory Storage (Future)

Combines subscriber + queryable into an in-memory key-value store.
Planned for a future phase.

### z_pong_shm — Pong Is SHM-Transparent

No such example exists in zenoh-c. The pong responder echoes whatever
bytes it receives regardless of SHM backing. `z_pong.dart` works
unchanged with both `z_ping.dart` and `z_ping_shm.dart`.

---

## Examples

### z_put / z_delete — One-Shot Publish and Delete

**Follows canon.**

These are the simplest zenoh operations. `z_put` publishes a single
key-value pair; `z_delete` removes a resource.

**The pattern it demonstrates**

```
z_put:    open session → put(key, value) → close       (one-shot write)
z_delete: open session → delete(key) → close           (one-shot remove)
```

The basic session lifecycle: open, operate, close. No long-lived
entities, no callbacks, no streams.

**Dart-specific note**

Both are synchronous FFI calls — no isolate, no async. The C shim wraps
`z_put()` / `z_delete()` primarily for options struct initialization
(barrier 3) and move semantics (barrier 1).

```
z_put.dart    -k demo/example/zenoh-dart-put  -p 'Put from Dart!'
z_delete.dart -k demo/example/zenoh-dart-put
```

| Flag | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/zenoh-dart-put` | Key expression |
| `-p, --payload` | `Put from Dart!` | Value to publish (z_put only) |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_sub — Callback Subscriber

**Follows canon** with Dart-specific async adaptation.

**The pattern it demonstrates**

```
z_sub: open → declareSubscriber(key) → stream<Sample> → ... → close   (long-lived, push)
```

Continuous message reception on a key expression. Runs until Ctrl-C.
zenoh-c uses a C callback invoked on a zenoh worker thread. Dart cannot
receive callbacks on non-Dart threads, so the C shim extracts all sample
fields synchronously during the callback and posts them to Dart via
`Dart_PostCObject_DL` / `NativePort`. Dart receives them as a `Stream<Sample>`.

This is the **NativePort callback bridge** — the foundational pattern
reused by every callback-based entity in the binding (subscriber,
queryable, scout, publisher matching listener, background subscriber).

**Why not `NativeCallable.listener`?** Dart 3.1 introduced
`NativeCallable.listener` as a higher-level callback API, but it uses
the same `SendPort`/`ReceivePort` mechanism internally. More critically,
zenoh-c's loaned pointers (`z_loaned_sample_t*`) are only valid during
the synchronous callback — by the time `NativeCallable.listener`
delivers the pointer to Dart asynchronously, the memory is invalid.
The C shim must extract fields synchronously regardless of which Dart
callback API is used. The current approach is battle-tested across all
phases and 370+ tests. Monitor `NativeCallable.isolateGroupBound`
(experimental) for a future alternative that could read loaned pointers
synchronously on the zenoh thread.

```
z_sub.dart -k 'demo/example/**'
```

| Flag | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/**` | Key expression |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_pub — Declared Publisher

**Follows canon.**

**The pattern it demonstrates**

```
z_pub: open → declarePublisher(key) → put(value) loop → close   (long-lived entity, periodic write)
```

A long-lived publisher entity that sends periodic messages. Supports
attachments, congestion control, priority, and a matching listener that
notifies when subscribers appear or disappear.

**Dart-specific note**

The matching listener uses the same NativePort bridge as subscribers,
delivering status changes as a `Stream<bool>`. `Timer.periodic` drives
the publish loop. Signal handling uses `ProcessSignal.sigint.watch()`.

```
z_pub.dart -k demo/example/zenoh-dart-pub -p 'Pub from Dart!' --add-matching-listener
```

| Flag | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/zenoh-dart-pub` | Key expression |
| `-p, --payload` | `Pub from Dart!` | Message payload |
| `-a, --attach` | -- | Attachment string |
| `--add-matching-listener` | false | Enable subscriber discovery |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_pub_shm — SHM Publisher

**Follows canon.**

**The pattern it demonstrates**

```
z_pub_shm: open → declarePublisher(key) → [alloc → fill → toBytes → put] loop → close
                                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                            per-iteration SHM alloc (correct but expensive)
```

Per-iteration shared memory publish: allocate SHM buffer, fill with
payload bytes, convert to `ZBytes`, publish. This is the basic SHM
pattern — correct but not optimal for latency-sensitive paths (see
`z_ping_shm` for the optimized pattern).

**Dart-specific note**

Direct pointer manipulation via `ShmMutBuffer.data` — the Dart equivalent
of writing through a `uint8_t*` in C. `ShmProvider.alloc()` returns
`ShmMutBuffer?` (null on failure) rather than throwing, following the
approved nullable-return design.

SHM features are compile-time guarded (`Z_FEATURE_SHARED_MEMORY`,
`Z_FEATURE_UNSTABLE_API`) and excluded on Android where POSIX `shm_open`
is unavailable in Bionic.

```
z_pub_shm.dart -k demo/example/zenoh-dart-pub -p 'Hello from SHM!'
```

| Flag | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/zenoh-dart-pub` | Key expression |
| `-p, --payload` | `Pub from Dart!` | Message payload |
| `--add-matching-listener` | false | Enable subscriber discovery |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_get / z_queryable — Query/Reply

**Follows canon.**

**The pattern it demonstrates**

```
z_get:       open → get(selector) → await stream<Reply> → close          (one-shot query)
z_queryable: open → declareQueryable(key) → await query → reply → ...    (long-lived responder)
```

The request/response pattern. `z_get` sends a query with a selector and
receives a stream of replies. `z_queryable` declares a responder that
answers incoming queries.

**Dart-specific adaptation**

zenoh-c uses callbacks for both sides. Dart uses `Stream<Reply>` for get
replies and `Stream<Query>` for queryable. The C shim extracts reply/query
fields during the synchronous callback (loaned-pointer lifetime constraint)
and posts them via NativePort.

**C shim case study:** The get/queryable implementation adds 10 C shim
functions. During architectural review, 4 were found to be
barrier-justified but currently unreachable — they add pull-accessors
(`zd_query_keyexpr`, `zd_query_parameters`, `zd_query_payload`) for data
already pushed via NativePort, plus `zd_query_sizeof` for an allocation C
handles internally. These are retained because: each has a genuine FFI
barrier, future examples may need pull-based access, and the cost is ~5
lines of trivial C per function. The YAGNI principle applies to
speculative features, not to completing a thin shim over an API already
being wrapped.

```
z_get.dart       -s 'demo/example/**' -t BEST_MATCHING -o 10000
z_queryable.dart -k demo/example/zenoh-dart-queryable -p 'Queryable from Dart!' --complete
```

| Flag (z_get) | Default | Description |
|------|---------|-------------|
| `-s, --selector` | `demo/example/**` | Query selector |
| `-p, --payload` | -- | Optional query payload |
| `-t, --target` | `BEST_MATCHING` | `BEST_MATCHING`, `ALL`, `ALL_COMPLETE` |
| `-o, --timeout` | `10000` | Timeout in ms |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

| Flag (z_queryable) | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/zenoh-dart-queryable` | Key expression |
| `-p, --payload` | `Queryable from Dart!` | Reply payload |
| `--complete` | false | Declare as complete queryable |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_get_shm / z_queryable_shm — SHM Query/Reply

**Follows canon.**

**The pattern it demonstrates**

```
z_get_shm:       open → alloc → fill → toBytes → get(selector, payload: shmBytes) → await stream<Reply> → close
z_queryable_shm: open → declareQueryable(key) → await query → alloc → fill → toBytes → replyBytes → ...
```

SHM zero-copy variants of get and queryable. `z_get_shm` allocates an SHM
buffer for the query payload. `z_queryable_shm` allocates SHM for reply
payloads. Both use `ZBytes` (which can be SHM-backed) through the same
`Session.get()` and `Query.replyBytes()` APIs — no separate SHM query
path needed.

**Dart-specific note**

`ZBytes.isShmBacked` detects SHM backing. On Android, this always returns
false (SHM excluded at compile time). Both examples fall back to regular
payloads if SHM allocation fails.

```
z_get_shm.dart       -s 'demo/example/**' -p 'Query from SHM!'
z_queryable_shm.dart -k demo/example/zenoh-dart-queryable -p 'SHM reply from Dart!'
```

Flags are identical to their non-SHM counterparts above.

---

### z_pull — Pull Subscriber

**Deviates from canon:** C-side ring buffer.

**The pattern it demonstrates**

```
z_pull: open → declarePullSubscriber(key, capacity) → [user presses Enter → tryRecv()] loop
                                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                       synchronous poll, no stream (pull, not push)
```

On-demand polling of buffered samples. The user presses Enter to pull;
`tryRecv()` returns the most recent sample or null. The ring buffer is
lossy — when full, it drops the oldest entry.

**Key architectural decision**

The ring buffer lives in C, not Dart. The reason is **freshness**.

If the ring buffer sat in Dart (after NativePort delivery), all samples
would cross the FFI boundary — including ones destined to be dropped.
When Dart's event loop stalls (GC pause, Flutter frame render), the
"surviving" samples in a Dart-side ring are stale: they were recent
when C posted them, but old by the time Dart processes them.

With a C-side ring buffer, drops happen before NativePort. Only surviving
samples cross FFI. If Dart stalls for 500ms and a sensor publishes at
100Hz, the 3 samples in a C-side ring of capacity 3 are from the last
30ms. In a Dart-side ring, they would be 500ms old.

```
C-side:  zenoh thread -> [ring buffer, drops oldest] -> tryRecv() -> Dart
Dart-side: zenoh thread -> NativePort -> [ring buffer] -> Dart
                                          ^^^^^^^^^^^^
                                          samples already stale if Dart stalled
```

**The "fat tryRecv" pattern:** `zd_pull_subscriber_try_recv()` is a
single synchronous FFI call that performs receive, loan, field extraction,
and drop internally. One FFI round-trip per poll. Dart never holds a
sample handle. This mirrors the NativePort push pattern (extract
everything in C) but inverts control — Dart pulls instead of C pushing.

**Return code note:** `z_try_recv()` returns positive codes (0 = OK,
1 = no data, 2 = disconnected) unlike the usual zenoh-c convention of
negative errors. The Dart side uses explicit value checks, not the `!= 0`
pattern used elsewhere.

```
z_pull.dart -k 'demo/example/**' -s 256
```

| Flag | Default | Description |
|------|---------|-------------|
| `-k, --key` | `demo/example/**` | Key expression |
| `-s, --size` | `256` | Ring buffer capacity |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_info / z_scout — Session Info and Discovery

**Follow canon.**

**The pattern it demonstrates**

```
z_info:  open → zid → routersZid() → peersZid() → close   (session introspection)
z_scout: scout(config) → List<Hello> → print               (no session needed)
```

`z_info` prints the session's own ZenohId and the IDs of connected
routers and peers. `z_scout` discovers zenoh entities on the network
without opening a session.

**Dart-specific notes**

`ZenohId.toHexString()` does hex conversion in pure Dart — no FFI call,
despite `zd_id_to_string` existing in the C shim. Simpler with no
overhead.

`Zenoh.scout()` uses a NativePort variant: the C shim posts
`[zid, whatami, locators]` per discovered entity, then a null sentinel
on completion. Dart collects into `List<Hello>` via a `Completer`.

Router/peer ZID collection (`Session.routersZid()`, `Session.peersZid()`)
uses a synchronous buffer-based C closure (not NativePort) — the C shim
fills a caller-provided buffer, returns a count. This is the only
callback pattern in the binding that does not use NativePort, because
the data set is small and bounded.

```
z_info.dart
z_scout.dart
```

| Flag | Default | Description |
|------|---------|-------------|
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_querier — Declared Querier

**Follows canon.**

**The pattern it demonstrates**

```
z_querier: open → declareQuerier(selector, target, timeout) → [get() → stream<Reply>] loop → close
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                   fixed options at declaration, per-query payload varies
```

A long-lived querier entity for repeated queries. Declaration-time options
(target, consolidation, timeout) are fixed at creation; per-query options
(payload, encoding) vary per `get()` call. Includes a matching listener
for queryable discovery. Mirrors `Publisher` structurally — both are declared entities with
fixed options and per-operation parameters. `Querier.get()` returns
`Stream<Reply>` reusing the same reply callback infrastructure as
`Session.get()`.

```
z_querier.dart -s 'demo/example/**' -t BEST_MATCHING --add-matching-listener
```

| Flag | Default | Description |
|------|---------|-------------|
| `-s, --selector` | `demo/example/**` | Query selector |
| `-p, --payload` | -- | Optional query payload |
| `-t, --target` | `BEST_MATCHING` | `BEST_MATCHING`, `ALL`, `ALL_COMPLETE` |
| `-o, --timeout` | `10000` | Timeout in ms |
| `--add-matching-listener` | false | Enable queryable discovery |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_liveliness / z_sub_liveliness / z_get_liveliness — Liveliness

**Follow canon.**

**The pattern it demonstrates**

```
z_liveliness:     open → declareLivelinessToken(key) → ... → close       (announce presence)
z_sub_liveliness: open → declareLivelinessSubscriber(key) → stream<Sample> → ...
                                                            PUT = appeared, DELETE = gone
z_get_liveliness: open → livelinessGet(key) → stream<Reply> → close      (snapshot query)
```

Entity presence detection. `z_liveliness` declares a token announcing the
entity is alive. `z_sub_liveliness` subscribes to token changes (PUT on
appearance, DELETE on disappearance or connectivity loss).
`z_get_liveliness` queries currently alive tokens.

**Dart-specific note**

All three reuse existing callback infrastructure — `z_sub_liveliness`
reuses the sample callback/drop pair from regular subscribers;
`z_get_liveliness` reuses the reply callback/drop pair from `Session.get()`.
No new callback patterns introduced.

```
z_liveliness.dart     -k group1/zenoh-dart
z_sub_liveliness.dart -k 'group1/**' --history
z_get_liveliness.dart -k 'group1/**' -o 10000
```

| Flag (z_liveliness) | Default | Description |
|------|---------|-------------|
| `-k, --key` | `group1/zenoh-dart` | Key expression |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

| Flag (z_sub_liveliness) | Default | Description |
|------|---------|-------------|
| `-k, --key` | `group1/**` | Key expression |
| `--history` | false | Get existing tokens on subscribe |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

| Flag (z_get_liveliness) | Default | Description |
|------|---------|-------------|
| `-k, --key` | `group1/**` | Key expression |
| `-o, --timeout` | `10000` | Timeout in ms |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

---

### z_ping / z_pong — Latency Benchmark

**Follow canon.**

**The pattern it demonstrates**

```
z_pong: open → bgSubscriber(test/ping) → publisher(test/pong) → [recv → echo] loop   (responder)
z_ping: open → publisher(test/ping) → bgSubscriber(test/pong) → [publish → await pong → measure] loop
                                                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                                  Completer resets each iteration
```

Round-trip latency measurement. `z_pong` echoes every message received
on `test/ping` back to `test/pong`. `z_ping` publishes a payload, waits
for the echo, and measures the round-trip time.

**What's new (added to the project)**

- `Session.declareBackgroundSubscriber()` — fire-and-forget subscriber
  returning `Stream<Sample>`, lives until session closes, no explicit
  close needed
- `Publisher.isExpress` parameter — disables message batching for lower
  latency
- `ZBytes.clone()` — shallow ref-counted copy (near-zero cost)
- `ZBytes.toBytes()` — read content as `Uint8List`

`z_pong` uses a background subscriber (no handle management) with an
express publisher (no batching delay). `z_ping` uses a `Completer` that
resets each iteration to synchronize the ping/pong round-trip — the Dart
equivalent of C's condition variable wait.

```
z_pong.dart
z_ping.dart 64 -n 100 -w 1000
```

| Flag (z_pong) | Default | Description |
|------|---------|-------------|
| `--no-express` | false | Disable express mode |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

| Flag (z_ping) | Default | Description |
|------|---------|-------------|
| `<PAYLOAD_SIZE>` | (required) | Payload size in bytes |
| `-n, --samples` | `100` | Number of ping measurements |
| `-w, --warmup` | `1000` | Warmup time in ms |
| `--no-express` | false | Disable express mode |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

**Output format:** `<size> bytes: seq=<i> rtt=<us>us, lat=<us>us`

---

### z_ping_shm — SHM Latency Benchmark

**Composition example.** Zero new C shim functions, zero new Dart API.
Composes from `z_pub_shm`, `z_ping/z_pong`, `ZBytes.clone()`, and
`ZBytes.isShmBacked`.

**What's new**

- 1 CLI example: `z_ping_shm.dart` — allocate-once, clone-in-loop SHM
  benchmark
- ~10 tests: SHM clone integration (6) + CLI tests (4)

**Key architectural decision**

The phase spec mentions `ShmBuffer` / `toImmutable()` as an intermediate
type. This binding skips it — the existing `ShmMutBuffer.toBytes()`
already calls `z_bytes_from_shm_mut` which produces SHM-backed bytes
directly. The intermediate `z_owned_shm_t` type is a C API artifact for
explicit type transitions that Dart does not need. Adding `ShmBuffer`
would be dead API surface with no consumer.

**The pattern it demonstrates**

```
z_pub_shm:  alloc -> fill -> toBytes -> publish         (per iteration -- expensive)
z_ping_shm: alloc -> fill -> toBytes -> clone -> publish (clone in loop -- near free)
```

The allocate-once, clone-in-loop pattern is the production SHM
optimization. `ZBytes.clone()` increments a reference count — no memory
allocation, no data copy. This is the raison d'etre of SHM in
latency-sensitive paths.

**Test gap it fills**

No prior test covers `ZBytes.clone()` on SHM-backed bytes, or verifies
`isShmBacked` on `ShmMutBuffer.toBytes()` output. This example's test
suite closes that gap.

```
z_ping_shm.dart 64 -n 100 -w 1000
```

| Flag | Default | Description |
|------|---------|-------------|
| `<PAYLOAD_SIZE>` | (required) | SHM payload size in bytes |
| `-n, --samples` | `100` | Number of ping measurements |
| `-w, --warmup` | `1000` | Warmup time in ms |
| `--no-express` | false | Disable express mode |
| `-e, --connect` | -- | Connect endpoint(s) |
| `-l, --listen` | -- | Listen endpoint(s) |

**Pong side:** Reuses `z_pong.dart` unchanged. The pong subscriber
receives bytes transparently (SHM or heap) and echoes them back.

---

## Coverage Map

Which zenoh-c examples does this binding implement, and which are absent?

| zenoh-c Example | zenoh-dart | Status |
|-----------------|------------|--------|
| `z_put.c` | `z_put.dart` | Implemented |
| `z_delete.c` | `z_delete.dart` | Implemented |
| `z_sub.c` | `z_sub.dart` | Implemented |
| `z_pub.c` | `z_pub.dart` | Implemented |
| `z_pub_shm.c` | `z_pub_shm.dart` | Implemented |
| `z_info.c` | `z_info.dart` | Implemented |
| `z_scout.c` | `z_scout.dart` | Implemented |
| `z_get.c` | `z_get.dart` | Implemented |
| `z_queryable.c` | `z_queryable.dart` | Implemented |
| `z_get_shm.c` | `z_get_shm.dart` | Implemented |
| `z_queryable_shm.c` | `z_queryable_shm.dart` | Implemented |
| `z_pull.c` | `z_pull.dart` | Implemented (C-side ring buffer) |
| `z_querier.c` | `z_querier.dart` | Implemented |
| `z_liveliness.c` | `z_liveliness.dart` | Implemented |
| `z_sub_liveliness.c` | `z_sub_liveliness.dart` | Implemented |
| `z_get_liveliness.c` | `z_get_liveliness.dart` | Implemented |
| `z_ping.c` | `z_ping.dart` | Implemented |
| `z_pong.c` | `z_pong.dart` | Implemented |
| `z_ping_shm.c` | `z_ping_shm.dart` | Implemented |
| `z_sub_shm.c` | -- | Absent (subscriber is SHM-transparent) |
| `z_bytes.c` | -- | Absent (Dart has `dart:convert`) |
| `z_queryable_with_channels.c` | -- | Absent (Dart Streams) |
| `z_non_blocking_get.c` | -- | Absent (Dart Streams) |
| `z_advanced_pub.c` | -- | Future |
| `z_advanced_sub.c` | -- | Future |
| `z_pub_thr.c` | -- | Future |
| `z_sub_thr.c` | -- | Future |
| `z_pub_shm_thr.c` | -- | Future |
| `z_storage.c` | -- | Future |

**Current:** 19 implemented, 4 permanently absent, 6 future.

---

## Architectural Notes

### The NativePort Callback Bridge

zenoh-c delivers events (samples, replies, queries, scouting results)
via C callbacks invoked on zenoh's tokio worker threads. Dart isolates
are single-threaded and cannot receive foreign-thread callbacks directly.

The bridge works as follows:

1. Dart creates a `ReceivePort` and passes its `nativePort` (int64) to C
2. C stores the port in a heap-allocated context struct
3. When zenoh invokes the callback (on a tokio thread), the C shim:
   - Extracts all fields from the loaned pointer synchronously
   - Packs them into a `Dart_CObject` array
   - Calls `Dart_PostCObject_DL(port, &cobject)`
4. Dart's event loop receives the message and constructs the Dart object
5. When the entity is closed, zenoh calls the drop closure, which frees
   the context struct

The critical invariant: **loaned pointers are only valid during the
synchronous callback.** The C shim must extract data before returning.
No Dart-side API (`NativeCallable.listener`, `Pointer.fromFunction`) can
solve this — it is structural to zenoh-c's ownership model.

### The Sole Facade Principle

Dart has zero direct bindings to zenoh-c. The `ffigen.yaml` filters on
`zd_.*` — only symbols with the `zd_` prefix appear in `bindings.dart`.
Dart literally cannot see `z_get()`, `z_declare_queryable()`, or any
other zenoh-c function.

The alternative — dual-binding with selective shimming — was rejected
because almost every zenoh-c call chain hits at least one FFI barrier
(a loan, a move, an options init). Shimming the loan, calling the
function directly, then shimming the drop is worse than shimming the
whole operation. A single `zd_*` namespace eliminates "which do I call?"
confusion and removes the per-phase audit burden of classifying functions.

### Callback Reuse Across Examples

Several callback implementations are shared:

| Callback pair | Used by |
|---------------|---------|
| `_zd_sample_callback` / `_zd_sample_drop` | subscriber, liveliness subscriber, background subscriber |
| `_zd_reply_callback` / `_zd_get_drop` | `Session.get()`, `Querier.get()`, `Session.livelinessGet()` |

This is a consequence of zenoh-c using the same data types (`z_loaned_sample_t`,
`z_loaned_reply_t`) across different features. The C shim mirrors this —
one extraction function per data type, not per feature.

---

## Updating This Guide

When a new example is implemented, add an entry in the Examples section
using this template:

```markdown
### z_example_name — Short Description

**Follows canon / Deviates from canon / Composition example.**

Brief classification. If composition: list which existing primitives
it composes. If deviation: state what differs.

**What's new**

- N CLI example(s): description
- ~N tests: breakdown

**The pattern it demonstrates**

Arrow-chain showing the operation sequence. Every example gets one —
this is the visual signature. Use annotations under the chain to
highlight the key step. For compositions, contrast with the prior
example it builds on.

**Key architectural decision** (deviations and compositions only)

What the canon specifies, what we do instead, and why. Reference the
specific zenoh-c/zenoh-cpp construct being replaced or skipped.

**Test gap it fills** (if applicable)

What compositional invariant was untested before this example.

Flags table and usage line.
```

Update the Coverage Map table to reflect the new example's status.
