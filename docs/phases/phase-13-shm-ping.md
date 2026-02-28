# Phase 13: z_ping_shm (SHM Latency Test)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 4 (Core SHM) — completed
- SHM provider, alloc, mutable/immutable buffers, bytes conversion, SHM detection
- Dart: `ShmProvider`, `ShmMutBuffer`, `ShmBuffer`

### Phase 12 (Ping/Pong) — completed
- Background subscriber, `ZBytes.clone()`, `ZBytes.toBytes()`, publisher express mode
- CLI: `packages/zenoh/bin/z_pong.dart`, `packages/zenoh/bin/z_ping.dart`

## This Phase's Goal

SHM variant of the ping/pong latency test. Key pattern: **allocate once,
clone references in a loop** — demonstrates zero-copy SHM reuse.

**Reference example**: `extern/zenoh-c/examples/z_ping_shm.c`

### SHM ping pattern

Unlike non-SHM ping (which copies payload bytes each publish), SHM ping:
1. Allocates a single SHM buffer from the provider
2. Converts to immutable SHM → bytes
3. In the ping loop, clones the bytes reference (shallow copy — same underlying SHM)
4. Each `publisher.put(shmBytes.clone())` publishes the same shared memory with minimal overhead

The pong side reuses the existing `packages/zenoh/bin/z_pong.dart` from Phase 12 (it works
with both SHM and non-SHM payloads transparently).

## C Shim Functions Needed

No new C shim functions — this phase composes existing functions:
- `zd_shm_provider_default_new` (Phase 4)
- `zd_shm_provider_alloc` (Phase 4)
- `zd_shm_from_mut` (Phase 4)
- `zd_bytes_from_shm` (Phase 4)
- `zd_bytes_clone` (Phase 12)
- `zd_declare_background_subscriber` (Phase 12)
- `zd_declare_publisher` (Phase 3)
- `zd_publisher_put` (Phase 3)

## Dart API Surface

### Modify `packages/zenoh/lib/src/shm_buffer.dart`

Add method to convert mutable to immutable:

```dart
class ShmMutBuffer {
  /// Convert to an immutable SHM buffer (consumes this mutable buffer).
  ShmBuffer toImmutable();
}
```

This may already exist from Phase 4. If not, add it now.

### No other new API needed

All functionality composes from existing classes.

## CLI Example to Create

### `packages/zenoh/bin/z_ping_shm.dart`

Mirrors `extern/zenoh-c/examples/z_ping_shm.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_ping_shm.dart [OPTIONS]

Options:
    -p, --payload-size <SIZE>  (default: 8)
    -n, --samples <NUM>        (default: 100)
    -w, --warmup <MS>          (default: 1000)
```

Behavior:
1. Open session
2. Declare publisher on "test/ping" (express mode)
3. Declare subscriber on "test/pong"
4. Create SHM provider
5. Allocate SHM buffer of payload size
6. Fill buffer with data pattern
7. Convert: mutable → immutable → bytes
8. Warmup phase: publish shmBytes.clone() + wait for pong
9. Measurement phase:
   ```dart
   for (var i = 0; i < numPings; i++) {
     final sw = Stopwatch()..start();
     publisher.putBytes(shmBytes.clone());  // shallow ref copy
     await pongReceived.future;             // wait for pong
     final rtt = sw.elapsedMicroseconds;
     results.add(rtt);
   }
   ```
10. Print results (RTT, one-way latency in microseconds)
11. Close provider and session

## Key Difference from Non-SHM Ping

| Aspect | z_ping (Phase 12) | z_ping_shm (this phase) |
|--------|-------------------|------------------------|
| Payload creation | `ZBytes.fromBytes(Uint8List)` | `provider.alloc()` → `toImmutable()` → `toBytes()` |
| Per-publish cost | Deep copy of byte array | Shallow reference clone (nearly free) |
| Memory location | Dart heap | POSIX shared memory segment |
| Zero-copy | No | Yes — same SHM buffer shared across processes |

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Run `packages/zenoh/bin/z_pong.dart` + `packages/zenoh/bin/z_ping_shm.dart` — SHM ping with latency results
3. **Compare**: Run both `z_ping.dart` and `z_ping_shm.dart` against same `z_pong.dart` — SHM should show lower latency
4. **Unit test**: `ShmMutBuffer.toImmutable()` produces valid ShmBuffer
5. **Unit test**: `shmBytes.clone()` produces valid bytes that can be published
