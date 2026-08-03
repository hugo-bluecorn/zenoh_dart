# zenoh_dart

> ## 🎯 Where this is going — **v1.0.0, the Parity Release against Eclipse Zenoh 1.8.0**
>
> The target is a Dart binding *equivalent* to the canonical C and C++ bindings: the same
> capabilities, the same semantics, the same idioms, checked symbol by symbol against
> [`zenoh-c`](https://github.com/eclipse-zenoh/zenoh-c). That is **v1.0.0**, and it will be the
> first release intended for production use — see [Road to v1.0.0](#road-to-v100).
>
> **0.20.0 is the baseline it will be measured against**, published with its defects intact and
> catalogued in [Known issues](#known-issues-in-0200).

> ## ⚠️ NOT FOR PRODUCTION
>
> **Pre-1.0 and under active development. Good enough to experiment with — not good enough to
> build a product on.** Expect breaking changes without deprecation cycles.
>
> **Targets are narrow.** Linux `x86_64` and Android `armeabi-v7a` / `arm64-v8a` / `x86_64` only.
> macOS, Windows, iOS and web are unsupported — the build hook fails on those targets.
>
> **Android is feature-reduced, not merely a different platform.** Shared memory (`ShmProvider`,
> `ShmMutBuffer`, `ZBytes.isShmBacked`) and advanced pub/sub (`AdvancedPublisher`,
> `AdvancedSubscriber`) are compiled out — 131 exported shim symbols against Linux's 156. Calling
> them on Android fails at symbol lookup.
>
> **Versions `0.2.0` and earlier under this name are a different project**
> ([github.com/salimpia/zenoh_dart](https://github.com/salimpia/zenoh_dart)), transferred to this
> publisher. They share no code and no API with this package.

Pure Dart FFI bindings for [Eclipse Zenoh](https://github.com/eclipse-zenoh) — the pub/sub, query
and storage protocol — wrapping [`zenoh-c`](https://github.com/eclipse-zenoh/zenoh-c) **v1.7.2**
through a thin C shim layer.

## Before you start

Three things are not obvious and will cost you time otherwise.

**Configuration values are JSON5, so strings need their quotes.** `Config` currently exposes only
`insertJson5` — there is no way to load a configuration *file* (see
[Structurally absent](#structurally-absent)).

```dart
final config = Config();

// Connect to a router. Note the nested quotes — the value is JSON5.
config.insertJson5('connect/endpoints', '["tcp/127.0.0.1:7447"]');

// Client mode. insertJson5('mode', 'client') FAILS — the value must be a JSON5 string.
config.insertJson5('mode', '"client"');

// Turn off multicast discovery (useful in tests and on noisy networks).
config.insertJson5('scouting/multicast/enabled', 'false');

final session = Session.open(config: config);
```

**Every declared entity needs its own `close()`.** `Session.close()` does **not** cascade. Leaving a
`Subscriber`, `Queryable`, `AdvancedSubscriber` or liveliness subscriber open keeps its receive port
alive and **the Dart VM will never exit**, even after the session is closed. (`Publisher`,
`PullSubscriber`, `Querier`, `LivelinessToken` and `declareBackgroundSubscriber` are safe.)

**The API is synchronous and blocks the calling isolate.** `Session.open()` takes roughly half a
second in peer mode on an idle host, and seconds in client mode against an unreachable router. In
Flutter, do it off the frame path.

**Enable logging before opening a session** — otherwise failures surface only as an exception code:

```dart
Zenoh.initLog('error');  // or 'info', 'debug'
```

## Features

- Peer-to-peer and routed communication via zenoh
- Publish/subscribe with key expressions
- Query/reply (get/queryable) request-response
- Pull subscriber with a ring buffer (lossy, drop-oldest)
- Declared querier for repeated queries, with matching status
- Liveliness tokens for presence detection
- Background subscriber (fire-and-forget, lives until the session closes)
- Ping/pong latency and throughput benchmarking (heap and SHM)
- Cross-language typed serialization (`ZSerializer` / `ZDeserializer`)
- Raw byte assembly (`ZBytesWriter`) and fragmented slice iteration
- Byte-exact binary payload **and attachment** delivery — protobuf, flatbuffers and CDR safe — via
  `payloadBytes` / `attachmentBytes`, with attachment and encoding send options and error replies
- Advanced pub/sub: publisher cache, history recovery, sample miss detection with heartbeats
- Key expression matching (`intersects` / `includes` / `equals`)
- Shared memory zero-copy for publish, get and reply (Linux) — verified interoperating with a C
  `z_sub_shm` peer, which classifies the payload as SHM
- Network scouting and session info
- Build hooks for native library distribution

## Getting Started

```dart
import 'package:zenoh_dart/zenoh.dart';

void main() async {
  Zenoh.initLog('error');
  final session = Session.open();

  // Subscribe first, so the put below is actually delivered.
  final subscriber = session.declareSubscriber('demo/**');
  subscriber.stream.listen((sample) {
    print('${sample.keyExpr}: ${sample.payload}');
  });

  session.put('demo/hello', 'Hello from Dart!');

  final publisher = session.declarePublisher('demo/counter');
  publisher.put('value');

  await Future<void>.delayed(const Duration(milliseconds: 200));

  // Close every declared entity, then the session — see "Before you start".
  subscriber.close();
  publisher.close();
  session.close();
}
```

Binary payloads **and attachments** round-trip byte-exact. Publish with
`putBytes(key, ZBytes.fromUint8List(bytes), attachment: ZBytes.fromUint8List(meta))` and read
`sample.payloadBytes` / `sample.attachmentBytes` on receive. The `payload` and `attachment` Strings
are lenient display views — invalid UTF-8 renders as U+FFFD.

## API

| Class | Description |
|-------|-------------|
| `Zenoh` | Static utilities: `initLog()`, `scout()` |
| `Config` | Session configuration via JSON5 insertion |
| `Session` | Open/close sessions; put, subscribe, publish, get, queryable, pull subscribe, querier, liveliness, background subscribe, advanced publish/subscribe |
| `KeyExpr` | Key expression creation and validation; `intersects()`/`includes()`/`equals()` |
| `ZBytes` | Binary payload container; `clone()`, `toBytes()`, `fromInt()`/`toInt()`, `fromDouble()`/`toDouble()`, `fromBool()`/`toBool()`, `slices`, `isShmBacked` |
| `ZSerializer` | Streaming serializer (uint8–int64, float, double, bool, string, bytes, sequence length) |
| `ZDeserializer` | Streaming deserializer with `isDone` state tracking |
| `ZBytesWriter` | Raw byte assembler: `writeAll()`, `append()` (consumed), `finish()` |
| `LivelinessToken` | Announces entity presence; intersecting subscribers notified on declare/close |
| `Publisher` | Declared publisher: `put()`, `putBytes()`, `deleteResource()`, matching status; `isExpress` set at declaration |
| `AdvancedPublisher` | Publisher with cache, publisher detection and sample miss detection |
| `AdvancedPublisherOptions` | Cache size, publisher detection, miss detection, heartbeat mode/period |
| `HeartbeatMode` | Enum: `none`, `periodic`, `sporadic` |
| `Subscriber` | Callback-based subscriber delivering `Stream<Sample>` |
| `AdvancedSubscriber` | Subscriber with history recovery, late publisher detection and miss events |
| `AdvancedSubscriberOptions` | History, recovery, miss detection, subscriber detection, miss listener |
| `MissEvent` | Missed-sample notification with source `ZenohId` and count |
| `PullSubscriber` | Ring-buffer pull subscriber with `tryRecv()` (lossy, drop-oldest) |
| `Querier` | Declared querier for repeated queries, with matching status |
| `Query` | Received query; `reply`/`replyBytes`/`replyErr`/`replyErrBytes`/`dispose`; `payloadBytes`, `attachmentBytes` |
| `Queryable` | Callback-based queryable delivering `Stream<Query>` |
| `Reply` | Tagged union: `isOk`, `ok` (Sample), `error` (ReplyError) |
| `ReplyError` | Error reply with payload and encoding |
| `QueryTarget` | Enum: `bestMatching`, `all`, `allComplete` |
| `ConsolidationMode` | Enum: `auto`, `none`, `monotonic`, `latest` |
| `Sample` | Received data: `keyExpr`, `payload` (lenient display string), `payloadBytes` (exact), `kind`, `encoding`, `attachment`, `attachmentBytes` (exact) |
| `SampleKind` | Enum: `put`, `delete` |
| `Encoding` | MIME type wrapper with 10 predefined constants |
| `CongestionControl` | Enum: `block`, `drop` |
| `Priority` | 7 levels, `realTime` to `background` |
| `ShmProvider` | POSIX shared memory provider for zero-copy |
| `ShmMutBuffer` | Mutable SHM buffer |
| `ZenohId` | 16-byte session identifier |
| `WhatAmI` | Enum: `router`, `peer`, `client` |
| `Hello` | Scouting result: ZID, type, locators |
| `ZenohException` | Error type for zenoh operations |

## CLI Examples

26 examples mirroring `zenoh-c`'s `z_*.c`, in
[`package/example/`](https://github.com/bluecorn/zenoh_dart/tree/main/package/example) — see the
[examples guide](https://github.com/bluecorn/zenoh_dart/blob/main/package/example/README.md) for a
per-example walkthrough.

Most accept `-e`/`--connect` and `-l`/`--listen`; `z_delete.dart` takes only `-k`, and `z_bytes.dart`
takes no flags. **None implements canon's `-c/--config`, `-m/--mode`, `--cfg`,
`--no-multicast-scouting` or `-h/--help`** — see [Known issues](#known-issues-in-0200).

```bash
dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'
dart run example/z_sub.dart -k 'demo/example/**'
dart run example/z_get.dart -s 'demo/example/**'
dart run example/z_queryable.dart -k demo/example/zenoh-dart-queryable
dart run example/z_querier.dart -s 'demo/example/**'
dart run example/z_pull.dart -k 'demo/example/**'
dart run example/z_liveliness.dart -k group1/zenoh-dart
dart run example/z_sub_liveliness.dart -k 'group1/**' --history
dart run example/z_pong.dart
dart run example/z_ping.dart 64 -n 100 -w 1000
dart run example/z_pub_thr.dart 8192 --express
dart run example/z_sub_thr.dart -s 10 -n 100000
dart run example/z_pub_shm_thr.dart 8192 -s 1
dart run example/z_bytes.dart
```

> **`z_pub_shm_thr` needs a raised locked-memory limit.** Its `-s` default of **32 MB** mirrors
> zenoh-c's example — parity, not a tuning choice. Most Linux distributions cap `ulimit -l` at 8 MB
> and the provider then fails with `Unable to create POSIX shm segment: OS error 12`. Pass a smaller
> pool (`-s 1`), or raise the limit — note the *hard* limit is usually 8 MB too, so raising it needs
> root via `/etc/security/limits.conf` or a systemd `LimitMEMLOCK=` override, not just `ulimit -l`
> in your shell.

## Demo applications

Two Flutter applications we maintain drive a PincherX-100 robot arm over Zenoh using this package.
Both run against a simulator in Docker with rviz — no hardware required.

| App | What it demonstrates |
|-----|----------------------|
| [flutter_zenoh_gateway](https://github.com/bluecorn/flutter_zenoh_gateway) | App → Zenoh → a thin C++ Zenoh↔ROS gateway node → arm. JSON commands in, `interbotix_xs_msgs` out. |
| [flutter_zenoh_direct](https://github.com/bluecorn/flutter_zenoh_direct) | No gateway node — the app *is* the ROS-over-Zenoh participant. Reads `joint_states`, computes FK, writes `JointGroupCommand` as CDR. |

Each repository's README states the `zenoh_dart` version it targets. Background:
[Building a UI for Robotics Using Flutter and Zenoh](https://github.com/bluecorn/flutter-zenoh-robotics-ui-webinar).

## Platform Support

Built and tested on the **current and previous Ubuntu LTS** (26.04, 24.04). Other Linux
distributions are untested; the shipped prebuilt requires glibc ≥ 2.34.

| Platform | Architecture | Status | Notes |
|----------|--------------|--------|-------|
| Linux | x86_64 | Supported | Ubuntu LTS 24.04 / 26.04 |
| Android | armeabi-v7a, arm64-v8a, x86_64 | Supported | **`minSdkVersion` 24**; no SHM, no advanced pub/sub. These are Flutter's three default APK targets. |
| Android | x86 | Not shipped | Emulator-only ABI, and not a Flutter default target |
| Linux | arm64 and others | Not shipped | The build hook throws `PathNotFoundException` (Raspberry Pi, Jetson, ARM cloud) |
| macOS, Windows, iOS, web | — | Not supported | The build hook fails cleanly with `UnsupportedError` |

## How the native libraries are built

This package ships **prebuilt** native libraries — you do not need Rust, cargo, CMake or the Android
NDK to depend on it. Eight `.so` files, about 48 MB unpacked:

| Target | Files |
|---|---|
| `native/linux/x86_64/` | `libzenoh_dart.so`, `libzenohc.so` |
| `native/android/armeabi-v7a/` | `libzenoh_dart.so`, `libzenohc.so` |
| `native/android/arm64-v8a/` | `libzenoh_dart.so`, `libzenohc.so` |
| `native/android/x86_64/` | `libzenoh_dart.so`, `libzenohc.so` |

`libzenohc.so` is [zenoh-c](https://github.com/eclipse-zenoh/zenoh-c) itself, built from tag
**1.7.2**. `libzenoh_dart.so` is this project's C shim, which flattens the macros, generic selections
and opaque types that cannot cross the Dart FFI boundary. The shim links the runtime via `DT_NEEDED`.
On Linux it also carries `RUNPATH=$ORIGIN`, so the two resolve from the same directory with no
`LD_LIBRARY_PATH`; on Android the APK's linker resolves them from `lib/<abi>/`.

**The sources are not in this package.** The publish boundary is `package/`, and every build input
lives above it in the repository:
[`src/`](https://github.com/bluecorn/zenoh_dart/tree/main/src) (the C shim),
[`CMakeLists.txt`](https://github.com/bluecorn/zenoh_dart/blob/main/CMakeLists.txt) and
`CMakePresets.json`, [`scripts/`](https://github.com/bluecorn/zenoh_dart/tree/main/scripts), and the
`extern/zenoh-c` submodule. Clone the repository to build them yourself:

```bash
git clone --recurse-submodules https://github.com/bluecorn/zenoh_dart
cd zenoh_dart

# Linux x86_64 — zenoh-c from source, then the shim, installed into package/native/
cmake --preset linux-x64
cmake --build --preset linux-x64 --target install

# Android — all three shipped ABIs (needs the NDK and cargo-ndk)
./scripts/build_zenoh_android.sh --abi armeabi-v7a
./scripts/build_zenoh_android.sh
```

The Linux build uses the Rust toolchain that zenoh-c's `rust-toolchain.toml` pins — **1.85.0** —
which cargo selects on its own. The Android script builds through `cargo-ndk` with the `stable`
toolchain instead, so the three Android runtimes are compiled by whatever `stable` resolved to at
build time rather than by 1.85.0. Android builds target **API 24** and are 16 KB page-size aligned.

**Verifying what you got.** The shipped binaries are checkable without building anything:

```bash
# zenoh-c version baked into the runtime
strings libzenohc.so | grep -oE 'v1\.[0-9]+\.[0-9]+' | sort -u

# the rustc that compiled it
strings libzenohc.so | grep -oE 'rustc/[0-9a-f]+' | sort -u

# exported shim surface — 156 on Linux, 131 on Android
nm -D --defined-only libzenoh_dart.so | grep -c ' T zd_'
```

The Android builds export fewer symbols because shared memory and advanced pub/sub are compiled out
there — see [Platform Support](#platform-support).

## Known issues in 0.20.0

This release is published deliberately, with its defects intact and catalogued. It is the
**baseline** of a documented before/after — comparing it against [v1.0.0](#road-to-v100) is the
point.

Nothing here is speculative. Every item was verified in source, and several were reproduced by
running them. The three sections below are deliberately distinct: what is **already fixed** upstream,
what is **known and not yet fixed anywhere**, and what is **structurally missing** from the binding.

### Already fixed in the development tree — 18 defects

Fixed after this release's code was branched, arriving in a later release. The development
repository is private; **contact the maintainer** if you need to inspect the fixes.

**Data fidelity (5).** `ZBytes.toStr()` throws on any non-UTF-8 payload — it routes through a
UTF-8-*validating* extractor, so protobuf, flatbuffer and compressed payloads raise
`ZenohException`; use `toBytes()`. `ZDeserializer.deserializeString()` throws `FormatException` on
non-UTF-8 for the same reason — a canon peer's arbitrary bytes cannot be read back.
`ZBytes.fromString` and `ZSerializer.serializeString` both truncate at the first embedded NUL. Scout
locators are `';'`-joined then re-split, so a locator containing `;` arrives fragmented.

**Resources (4).** `ZBytes.markConsumed()` leaks its wrapper block on every send — 32–40 bytes per
message depending on build variant, unreclaimable by any caller (the fix commit measures 46.40
bytes/iteration before, 0.08 after). `Session.open()` leaks 2008 bytes per call and drops an
already-moved handle on the failure path. `ZBytesWriter.append` marks its argument consumed *after*
the error throw — a latent use-after-move. `Zenoh.scout` marks the config consumed *before* the call;
inert today only because of the leak above, so the two must be fixed together.

**Concurrency (1).** `Zenoh.scout()` blocks the calling isolate for the whole timeout — it returns a
`Future`, but no timer fires and no other future progresses until it completes. (Provably the only
one of its class: this library exposes exactly one `Future`-returning API.)

**Canon parity (8).** Publisher congestion control defaults to `block`; zenoh-c defaults to `drop`.
`Session.get()` hardcodes a **default** 10 s timeout, ignoring `queries_default_timeout` from the
session config — a caller can still override it. `routersZid()`/`peersZid()` silently truncate at 64
entries (the fix raises this to 1024; true-unbounded enumeration is [item 9](#road-to-v100)).
**`Session.get()` rejects any selector containing `?`** — it validates the whole selector as a key
expression, so `get('demo/**?_time=[now(-1h)..]')` throws; pass parameters via the separate
`parameters:` argument. `WhatAmI.fromInt` throws on an unrecognised bitmask, which strands `scout()`'s
completer forever. `ZBytes.isShmBacked` throws on Android instead of returning `false`.
`Zenoh.scout` discards the shim's return code, so a failed scout silently returns `[]`. Five shim
call sites discard return codes — including `z_config_default` at `src/zenoh_dart.c:756`, where the
config is left **uninitialized** and moved into `z_scout` regardless.

### Known and not yet fixed — 4 defects

These are measured and unfixed in every tree. They are listed because a catalogue that omits them
would be misleading.

- **`ZenohId.toHexString()` disagrees with every other zenoh implementation.** Two divergences:
  canon renders the 16 bytes as a **little-endian** integer (ours walks the array forward, producing
  the exact byte reversal), and canon **strips leading zeros** (ours pads to 32 characters). Measured
  against a C `z_info` peer on the same session: canon `320759394c29738a41b76a2de58c635d`, ours
  `5d638ce52d6ab7418a73294c39590732`. **A ZID logged by this binding cannot be matched against router
  logs, `zenohd` output, or any other binding.** Affects `Session.zid`, `routersZid()`, `peersZid()`,
  `Hello.zid` and `MissEvent.sourceId`. The correct primitive exists in the shim and is not called.
- **`Query` handles leak.** One wrapper block per received query, never freed — unbounded in a
  long-running queryable.
- **`Session.open()` blocks the calling isolate** for ~500 ms in peer mode, seconds in client mode
  against an unreachable router. The whole API is synchronous.
- **A declared entity that is not closed keeps the Dart VM alive forever**, even after
  `Session.close()`. Affects `Subscriber`, `Queryable`, `AdvancedSubscriber` and liveliness
  subscribers.

### Structurally absent

Capabilities canon has that this binding does not expose at all. These are not bugs in what exists —
they are things that are missing.

- **No way to load a configuration file.** `Config` exposes only `insertJson5`. Canon has
  `from_env`, `from_file`, `from_str`, `to_string` and `get`. Every zenoh-c example accepts
  `-c <file>`; this binding cannot.
- **No receive-side sample metadata.** `Sample` carries no `timestamp`, `source_info`, `priority`,
  `congestion_control` or `express`; `Reply` has no `replier_id`; `Query` has no `encoding` or
  `accepts_replies`. The timestamp gap is the sharpest: `AdvancedPublisher` requires
  `timestamping/enabled`, and `z_storage.dart` is presented as a storage — while nothing can read
  the timestamp a storage exists to reconcile on.
- **A queryable cannot reply with a DELETE.** `z_query_reply_del` has no wrapper.
- **No error detail.** `ZenohException` carries a generic message and a raw code; the actual reason
  appears only in zenoh's stderr tracing, and only if the log level admits it. Canon's
  `zc_last_error_message` is unbound.
- **Seven exported shim symbols are unreachable** from the Dart API.

### Examples — five parity defects

- **`z_get` / `z_get_shm` throw on any selector containing `?params`** (the library defect above,
  surfaced through the examples). `z_querier` splits correctly, so the corpus is inconsistent.
- **`z_storage` replies with the lenient UTF-8 display string**, re-encoding invalid bytes as U+FFFD.
  Reproduced: a 3-byte payload `[8, 150, 1]` returns as 5 bytes `[8, 239, 191, 189, 1]` — content
  *and* length change, silently.
- **`z_querier` issues queries on an unawaited timer**, so drains overlap — roughly ten queries in
  flight at the default timeout, with repeating indices.
- **`z_pull` drains the entire ring per keypress**; canon does exactly one `try_recv` per input
  character. Its `-s` default is 256 against canon's 3, and it lacks canon's `-i/--interval`.
- **`z_ping` builds its payload inside the timed window**, inflating measurements — about +0.3 µs at
  64 B rising to +44 µs at 64 KiB, distorting the shape of the latency curve, not just its offset.
  (`z_ping_shm` is correct; the C examples differ from each other here, and ours matches each.)

All five are fixed in the development tree.

### Examples — CLI surface

**No example implements canon's common flags** — `-c/--config`, `-m/--mode`, `--cfg`,
`--no-multicast-scouting`, `-h/--help`. `-h` produces a Dart stack trace instead of help, and an
unknown option raises an unhandled `FormatException` where canon prints a message and exits.
**`z_delete` accepts only `-k`** and opens its session with no config, so it cannot be pointed at a
router without multicast scouting. **`z_pub_shm` publishes on `z_pub`'s key**, so running both feeds
one subscriber from two sources. **`z_bytes` exits 0 even when every section prints FAIL.**
**Ten examples set the log level to `info`** where every canon example uses `error`, flooding stdout
— and for `z_ping`/`z_pong` putting tracing on the measured path. Several defaults and output strings
differ from canon (`z_sub_thr`'s message count is 10× low; `z_ping` prints `us` for `µs`; index
padding differs, which changes the **bytes on the wire**). All fixed in the development tree.

### Tests

The suite is **571 tests, 569 passing** when run serially (`dart test --concurrency=1` — this package
ships no `dart_test.yaml`, and the tests open real zenoh sessions that contend for the network, so
parallel runs fail spuriously).

**Read that number with care.** The two failures are environmental — `z_pub_shm_thr_cli_test.dart`
requests canon's 32 MB pool against an 8 MB locked-memory limit. But the suite also contains
**roughly twenty tests that cannot fail**: ten in `serializer_test.dart` assert `isNotNull` on a
non-nullable return; `z_queryable_shm_cli_test.dart` never sends a query, so the example's entire
subject has no executed coverage; `z_pong_cli_test.dart` asserts the key expression and nothing about
the payload, leaving echo fidelity untested; a `CongestionControl.drop` test passes no
`congestionControl` argument. Separately, 19 test files define a process-kill helper and only one
registers it, so a timed-out child can survive and answer a later test's traffic. All of this is
repaired in the development tree; **do not read 569 as a coverage claim.**

## Road to v1.0.0

Systematic parity work began in **June 2026** with a census of the `zenoh-c` **1.7.2** API surface —
every symbol individually dispositioned against this binding:

| Disposition | Count |
|---|---|
| Excluded as binding-internal plumbing | 351 |
| Implemented | 148 |
| Deliberately deferred | 126 |
| Equivalent by design in Dart | 99 |
| **Missing** | **47** |
| **Partial** | **14** |
| **Total** | **785** |

Those **61 gaps**, the idiom-translation register compiled alongside the census, and three items that
later verification passes added — including one stable capability the census itself had missed —
became the eleven items below. The roadmap was locked in July 2026 and reopened for audit in August.

The `zenoh-c` pin moved from 1.7.2 to **1.8.0** in July 2026, *before* the roadmap was locked; every
item below is scoped against 1.8.0, and 0.20.0 is the last release on the 1.7.2 pin. Re-censusing
against 1.8.0 added 94 symbols and removed 2 (877 total), of which 72 are a new unstable subsystem
deferred as a dated carve-out; exactly one new stable capability entered the gap list.

| # | Scope | Kind |
|---|---|---|
| 1 | **Scout off the caller isolate** — `Zenoh.scout()` stops freezing the event loop | additive — ✅ merged |
| 2 | **Send-side options** — `congestionControl`, `priority` and `isExpress` on every send operation; a `Locality` enum on all five send paths *and* on subscriber/queryable declaration; `acceptReplies` on `get`/`declareQuerier` — each defaulting to canon's per-path default | additive |
| 3 | **Declared key expressions** — `declareKeyExpr`/`undeclareKeyExpr`, `String \| KeyExpr` accepted everywhere, plus `concat`/`join` | additive |
| 4 | **Key expression canonicalization** — `isCanon`, `canonize`, and a `KeyExpr.autocanonize` factory | additive |
| 5 | **Bounded pull channels** — a lossless FIFO delivery mode beside the lossy ring, and `tryRecv` widened to a sealed result distinguishing *empty* from *disconnected* | partial-breaking |
| 6 | **Bounded query/reply channels** — the same FIFO and ring modes for `Session.get()` and `declareQueryable`, with real producer backpressure | partial-breaking |
| 7 | **Shared-memory allocation surface** — a sealed three-way `AllocResult` replacing today's collapse-to-null, the full strategy matrix, alignment control, manual defragment/GC | partial-breaking |
| 8 | **Advanced pub/sub parity** — matching status on `AdvancedPublisher`, a detected-publishers stream and `keyExpr` on `AdvancedSubscriber`, `keyExpr` on plain `Subscriber` | additive |
| 9 | **Session identity** — truly unbounded ZID enumeration, a native ZID hex round-trip, `ZenohId` length validation | additive |
| 10 | **Encoding and serde ergonomics** — `Encoding.withSchema`, the full **53** predefined MIME constants (today: 10), single-shot `ZBytes.from`/`to` for every numeric width | additive |
| 11 | **Idiom alignment** — sealed `Reply`, non-nullable received `Encoding`, enhanced value-enums carrying wire values, `Set<WhatAmI>` for scout, value-class equality, and a defined session-scoped lifecycle for declared entities | **breaking, terminal** |

Item 11's lifecycle work may be split into its own item at planning time. **All breaking changes are
held for v1.0.0** — the items marked breaking land in that release, not before.

Then the **Parity Release**: every remaining *intentional* divergence from canon is closed or
recorded as a cited, dated carve-out with a canon-intrinsic reason — including a formal
re-justification of every stable deferral inherited from the census — the documentation is reconciled
against the shipped surface, and the result ships as **v1.0.0**.

## License

Apache 2.0 — see [LICENSE](LICENSE).
