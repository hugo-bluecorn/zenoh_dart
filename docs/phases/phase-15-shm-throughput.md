# Phase 15: z_pub_shm_thr (SHM Throughput Test)

## Project Context

`zenoh_dart` is a Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 4 (Core SHM) — completed
- SHM provider, alloc, mutable → immutable → bytes, SHM detection

### Phase 12 (Ping/Pong) — completed
- `ZBytes.clone()` (shallow reference copy)

### Phase 14 (Throughput) — completed
- CongestionControl, Priority enums, throughput publisher/subscriber
- CLI: `bin/z_pub_thr.dart`, `bin/z_sub_thr.dart`

## This Phase's Goal

SHM variant of the throughput publisher. Key pattern: **single SHM allocation,
reference cloning in a tight loop** for maximum throughput with zero per-message
allocation cost.

**Reference example**: `extern/zenoh-c/examples/z_pub_shm_thr.c`

### SHM throughput pattern

```c
// C pattern from z_pub_shm_thr.c:
// 1. Allocate ONCE
z_shm_provider_alloc(&alloc, z_loan(provider), args.size);
z_shm_from_mut(&shm, z_move(alloc.buf));
z_bytes_from_shm(&shmbs, z_move(shm));

// 2. Clone and reuse in tight loop
while (1) {
    z_owned_bytes_t payload;
    z_bytes_clone(&payload, z_loan(shmbs));  // Shallow ref copy
    z_publisher_put(z_loan(pub), z_move(payload), NULL);
}
```

In Dart:
```dart
final provider = ShmProvider(size: sharedMemorySize);
final buf = provider.alloc(payloadSize);
buf.data.asTypedList(payloadSize).fillRange(0, payloadSize, 1);
final shm = buf.toImmutable();
final shmBytes = shm.toBytes();

while (true) {
  publisher.putBytes(shmBytes.clone());  // shallow ref copy per publish
}
```

## C Shim Functions Needed

No new C shim functions — this phase composes existing functions:
- `zd_shm_provider_default_new` (Phase 4)
- `zd_shm_provider_alloc` (Phase 4)
- `zd_shm_from_mut` (Phase 4)
- `zd_bytes_from_shm` (Phase 4)
- `zd_bytes_clone` (Phase 12)
- `zd_declare_publisher_with_opts` (Phase 3)
- `zd_publisher_put` (Phase 3)

## Dart API Surface

No new API needed — all functionality composes from existing classes.

## CLI Example to Create

### `bin/z_pub_shm_thr.dart`

Mirrors `extern/zenoh-c/examples/z_pub_shm_thr.c`:

```
Usage: dart run bin/z_pub_shm_thr.dart [OPTIONS]

Options:
    -p, --payload-size <SIZE>        (default: 8)
    -m, --shared-memory <SIZE_MB>    (default: 32, SHM pool size in MB)
    --priority <PRIORITY>            (default: data)
    --express                        (flag)
```

Behavior:
1. Open session
2. Declare publisher with `congestionControl: CongestionControl.block`
3. Create SHM provider with shared memory pool
4. Allocate single buffer, fill with pattern
5. Convert: mutable → immutable → bytes
6. Tight loop: `publisher.putBytes(shmBytes.clone())`
7. Run until SIGINT
8. Close provider and session

**Note**: The subscriber side reuses `bin/z_sub_thr.dart` from Phase 14
(it works transparently with both SHM and non-SHM payloads).

## Key Difference from Non-SHM Throughput

| Aspect | z_pub_thr (Phase 14) | z_pub_shm_thr (this phase) |
|--------|---------------------|---------------------------|
| Payload source | Dart `Uint8List` → `ZBytes` | SHM provider → buffer → bytes |
| Per-publish cost | Deep copy of payload bytes | Shallow reference clone |
| Memory location | Dart heap → zenoh buffer | POSIX shared memory segment |
| Zero-copy | No | Yes |
| Expected throughput | Baseline | Higher (less allocation/copy overhead) |

## Verification

1. `flutter analyze` — no errors
2. **Integration test**: Run `bin/z_sub_thr.dart` + `bin/z_pub_shm_thr.dart` — subscriber reports throughput
3. **Compare**: Run `z_pub_thr.dart` and `z_pub_shm_thr.dart` with same subscriber — SHM should show higher throughput
4. **Unit test**: SHM provider with large pool allocates successfully
5. **Unit test**: Clone in tight loop doesn't leak (provider tracks references)
