# Phase 14: z_pub_thr + z_sub_thr (Throughput Test)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 3 (Publisher) — completed
- Declared publisher with put, options, matching listener

### Phase 12 (Ping/Pong) — completed
- Background subscriber, raw bytes, bytes clone, publisher express mode

## This Phase's Goal

Implement throughput benchmarks. The publisher sends data as fast as possible,
the subscriber counts messages and reports throughput (msg/s).

Key features:
- **Congestion control**: BLOCK mode (publisher blocks when network is congested)
- **Priority**: Configurable message priority levels
- **Express mode**: Disable batching for individual messages

**Reference examples**:
- `extern/zenoh-c/examples/z_pub_thr.c` — tight-loop publisher with congestion control
- `extern/zenoh-c/examples/z_sub_thr.c` — background subscriber counting messages

## C Shim Functions to Add

Publisher options are already available from Phase 3. The main additions are
enum accessors and ensuring the options fields are accessible:

```c
// No new C shim functions strictly required — the z_publisher_options_t struct
// already contains congestion_control, priority, and is_express fields.
// These are set through zd_publisher_options_default() + field assignment.
// However, for clean ffigen access, provide explicit setters:

FFI_PLUGIN_EXPORT void zd_publisher_options_set_congestion_control(
    z_publisher_options_t* opts, int congestion_control);

FFI_PLUGIN_EXPORT void zd_publisher_options_set_priority(
    z_publisher_options_t* opts, int priority);

FFI_PLUGIN_EXPORT void zd_publisher_options_set_express(
    z_publisher_options_t* opts, bool is_express);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c API |
|----------------|-------------|
| `zd_publisher_options_set_congestion_control` | Sets `z_publisher_options_t.congestion_control` |
| `zd_publisher_options_set_priority` | Sets `z_publisher_options_t.priority` |
| `zd_publisher_options_set_express` | Sets `z_publisher_options_t.is_express` |

Enum values from zenoh-c:
- `z_congestion_control_t`: `Z_CONGESTION_CONTROL_DROP` (0), `Z_CONGESTION_CONTROL_BLOCK` (1)
- `z_priority_t`: `Z_PRIORITY_REAL_TIME` (1), ..., `Z_PRIORITY_BACKGROUND` (7)

## Dart API Surface

### New file: `packages/zenoh/lib/src/enums.dart` (extend if exists)

```dart
/// Congestion control strategy for publishers.
enum CongestionControl {
  drop,   // Z_CONGESTION_CONTROL_DROP — drop messages on congestion
  block,  // Z_CONGESTION_CONTROL_BLOCK — block publisher on congestion
}

/// Message priority levels.
enum Priority {
  realTime,         // 1
  interactiveHigh,  // 2
  interactiveLow,   // 3
  dataHigh,         // 4
  data,             // 5
  dataLow,          // 6
  background,       // 7
}
```

### Modify `packages/zenoh/lib/src/session.dart`

Extend publisher declaration with new options:

```dart
Publisher declarePublisher(
  String keyExpr, {
  Encoding? encoding,
  CongestionControl congestionControl = CongestionControl.drop,  // NEW
  Priority priority = Priority.data,                             // NEW
  bool isExpress = false,
  bool enableMatchingListener = false,
});
```

## CLI Examples to Create

### `packages/zenoh/bin/z_pub_thr.dart`

Mirrors `extern/zenoh-c/examples/z_pub_thr.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_pub_thr.dart [OPTIONS]

Options:
    -p, --payload-size <SIZE>   (default: 8)
    --priority <PRIORITY>       (default: data)
    --express                   (flag)
```

Behavior:
1. Open session
2. Declare publisher with `congestionControl: CongestionControl.block`
3. Create payload of given size (filled with pattern)
4. Tight loop: publish payload clone as fast as possible
5. Run until SIGINT

### `packages/zenoh/bin/z_sub_thr.dart`

Mirrors `extern/zenoh-c/examples/z_sub_thr.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_sub_thr.dart [OPTIONS]

Options:
    -n, --samples <NUM>    (default: 100000, messages per measurement round)
    -r, --rounds <NUM>     (default: 10)
```

Behavior:
1. Open session
2. Declare background subscriber on "test/thr"
3. Count messages, measure time per round
4. Print throughput: `<msgs/s> msgs/s` for each round
5. Exit after all rounds

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Integration test**: Run `packages/zenoh/bin/z_sub_thr.dart` + `packages/zenoh/bin/z_pub_thr.dart` — subscriber reports throughput
3. **Integration test**: Run C `z_sub_thr` + Dart `z_pub_thr.dart` — cross-language throughput
4. **Unit test**: Publisher with CongestionControl.block works
5. **Unit test**: Publisher with different Priority values works
