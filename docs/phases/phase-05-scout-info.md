# Phase 5: z_scout + z_info (Discovery & Session Info)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0–3 (Core Pub/Sub) — completed
- Session/config/keyexpr/bytes, put/delete, subscriber (NativePort callback), publisher

### Phase 4 (Core SHM) — completed
- SHM provider, buffer alloc, mutable/immutable buffers, bytes conversion, SHM detection

## This Phase's Goal

Implement network discovery (`z_scout`) and session information queries (`z_info`).
Both are standalone — no counterpart needed to test against.

These examples validate the NativePort callback pattern with **different closure types**
(`z_owned_closure_hello_t`, `z_owned_closure_zid_t`) than the subscriber's
`z_owned_closure_sample_t`, proving the pattern generalizes.

**Reference examples**:
- `extern/zenoh-c/examples/z_scout.c` — discovers zenoh routers/peers on the network
- `extern/zenoh-c/examples/z_info.c` — queries session's own ID, routers, and peers

## C Shim Functions to Add

### Scouting

```c
// Scout for zenoh peers/routers. Hello messages are posted to dart_port.
// Scouting runs for a default timeout (~1 second), then posts a null/sentinel.
FFI_PLUGIN_EXPORT int zd_scout(
    z_owned_config_t* config,
    int64_t dart_port);
```

Internal callback `_zd_hello_callback` extracts from `z_loaned_hello_t`:
- ZID (16-byte array) via `z_hello_zid`
- whatami (int enum: router/peer/client) via `z_hello_whatami`
- locators (array of strings) via `z_hello_locators`

Posts to Dart port as array: `[zid_bytes, whatami_int, [locator1, locator2, ...]]`

### Session info

```c
// Get the session's own Zenoh ID
FFI_PLUGIN_EXPORT void zd_info_zid(
    const z_loaned_session_t* session,
    z_id_t* out);

// Get router ZIDs. Each ZID is posted to dart_port. Null sentinel at end.
FFI_PLUGIN_EXPORT void zd_info_routers_zid(
    const z_loaned_session_t* session,
    int64_t dart_port);

// Get peer ZIDs. Each ZID is posted to dart_port. Null sentinel at end.
FFI_PLUGIN_EXPORT void zd_info_peers_zid(
    const z_loaned_session_t* session,
    int64_t dart_port);
```

### ZID utilities

```c
// Convert a z_id_t to a hex string
FFI_PLUGIN_EXPORT void zd_id_to_string(const z_id_t* id, z_owned_string_t* out);

// Convert whatami enum to string
FFI_PLUGIN_EXPORT int zd_whatami_to_view_string(int whatami, z_view_string_t* out);
```

## zenoh-c APIs Wrapped

| C shim function | zenoh-c function(s) |
|----------------|---------------------|
| `zd_scout` | `z_scout`, `z_closure_hello`, `z_hello_zid`, `z_hello_whatami`, `z_hello_locators` |
| `zd_info_zid` | `z_info_zid` |
| `zd_info_routers_zid` | `z_info_routers_zid`, `z_closure_zid` |
| `zd_info_peers_zid` | `z_info_peers_zid`, `z_closure_zid` |
| `zd_id_to_string` | `z_id_to_string` |
| `zd_whatami_to_view_string` | `z_whatami_to_view_string` |

## Dart API Surface

### New file: `packages/zenoh/lib/src/id.dart`

```dart
/// A unique zenoh node identifier (16-byte ID).
class ZenohId {
  final Uint8List bytes;  // 16 bytes
  String toHexString();
}
```

### New file: `packages/zenoh/lib/src/hello.dart`

```dart
/// Information about a discovered zenoh node.
class Hello {
  final ZenohId? zid;
  final String whatami;  // "router", "peer", "client"
  final List<String> locators;
}
```

### New file: `packages/zenoh/lib/src/scout.dart`

```dart
/// Scout the network for zenoh routers and peers.
/// Returns a stream of Hello messages.
Stream<Hello> scout({Config? config});
```

### Modify `packages/zenoh/lib/src/session.dart`

Add properties/methods:

```dart
class Session {
  /// This session's Zenoh ID.
  ZenohId get zid;

  /// Get the ZIDs of connected routers.
  Future<List<ZenohId>> routersZid();

  /// Get the ZIDs of connected peers.
  Future<List<ZenohId>> peersZid();
}
```

### Modify `packages/zenoh/lib/zenoh.dart`

Add exports for `ZenohId`, `Hello`, `scout`.

## CLI Examples to Create

### `packages/zenoh/bin/z_scout.dart`

Mirrors `extern/zenoh-c/examples/z_scout.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_scout.dart
```

Behavior:
1. Scout the network
2. Print each discovered entity: whatami, ZID, locators
3. Exit when scouting completes

### `packages/zenoh/bin/z_info.dart`

Mirrors `extern/zenoh-c/examples/z_info.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_info.dart
```

Behavior:
1. Open session
2. Print own ZID
3. Print router ZIDs
4. Print peer ZIDs
5. Close session

## Verification

1. `cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml` — regenerate bindings
2. `fvm dart analyze packages/zenoh` — no errors
3. **Integration test**: Run `packages/zenoh/bin/z_scout.dart` with a zenoh router running — prints router info
4. **Integration test**: Run `packages/zenoh/bin/z_info.dart` connected to a router — prints ZIDs
5. **Unit test**: `ZenohId.toHexString()` produces valid hex string
6. **Unit test**: `Session.zid` returns non-zero ID after open
