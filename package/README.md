# zenoh

Pure Dart FFI bindings for the [Zenoh](https://zenoh.io/) pub/sub/query protocol.

## Features

- Peer-to-peer and routed communication via zenoh
- Publish/subscribe with key expressions
- Query/reply (get/queryable) request-response pattern
- Pull subscriber with ring buffer (lossy, latest-value semantics)
- Shared memory (SHM) zero-copy for publish, get, and reply (Linux)
- Network scouting and session info
- Build hooks for seamless native library distribution

## Getting Started

```dart
import 'package:zenoh/zenoh.dart';

void main() async {
  final session = Session.open(Config.defaultConfig());

  // Publish
  session.put(KeyExpr('demo/hello'), 'Hello from Dart!');

  // Subscribe
  final subscriber = session.declareSubscriber(KeyExpr('demo/**'));
  subscriber.stream.listen((sample) {
    print('${sample.keyExpr}: ${sample.payload}');
  });

  // Declare a publisher
  final publisher = session.declarePublisher(KeyExpr('demo/counter'));
  publisher.put('value');

  // Query/reply
  final replies = session.get('demo/**');
  await for (final reply in replies) {
    if (reply.isOk) print('${reply.ok.keyExpr}: ${reply.ok.payload}');
  }

  // Clean up
  subscriber.close();
  publisher.close();
  session.close();
}
```

## API

| Class | Description |
|-------|-------------|
| `Zenoh` | Static utilities: `initLog()`, `scout()` |
| `Config` | Session configuration with JSON5 insertion |
| `Session` | Open/close sessions; put, subscribe, publish, get, queryable, pull subscribe, querier |
| `KeyExpr` | Key expression creation and validation |
| `ZBytes` | Binary payload container; `isShmBacked` detects SHM backing |
| `Publisher` | Declared publisher with put/delete/matching status |
| `Subscriber` | Callback-based subscriber delivering `Stream<Sample>` |
| `PullSubscriber` | Ring-buffer-backed pull subscriber with `tryRecv()` (lossy) |
| `Querier` | Declared querier for repeated queries with matching status |
| `Query` | Received query with reply/replyBytes/dispose |
| `Queryable` | Callback-based queryable delivering `Stream<Query>` |
| `Reply` | Tagged union: `isOk`, `ok` (Sample), `error` (ReplyError) |
| `ReplyError` | Error reply with payload and encoding |
| `QueryTarget` | Enum: `bestMatching`, `all`, `allComplete` |
| `ConsolidationMode` | Enum: `auto`, `none`, `monotonic`, `latest` |
| `Sample` | Received data with key, payload, kind, encoding, attachment |
| `SampleKind` | Enum: `put`, `delete` |
| `Encoding` | MIME type wrapper with predefined constants |
| `CongestionControl` | Enum: `block`, `drop` |
| `Priority` | 7 priority levels from `realTime` to `background` |
| `ShmProvider` | POSIX shared memory provider for zero-copy |
| `ShmMutBuffer` | Mutable SHM buffer |
| `ZenohId` | 16-byte session identifier |
| `WhatAmI` | Enum: `router`, `peer`, `client` |
| `Hello` | Scouting result with ZID, type, and locators |
| `ZenohException` | Error type for zenoh operations |

## CLI Examples

All examples live in [`example/`](example/) and support `-e`/`--connect` and `-l`/`--listen` flags for endpoint configuration.

| Example | Description |
|---|---|
| [`z_put.dart`](example/z_put.dart) | Put data on a key expression |
| [`z_delete.dart`](example/z_delete.dart) | Delete a key expression |
| [`z_sub.dart`](example/z_sub.dart) | Subscribe to a key expression (runs until Ctrl-C) |
| [`z_pub.dart`](example/z_pub.dart) | Publish in a loop (runs until Ctrl-C) |
| [`z_pub_shm.dart`](example/z_pub_shm.dart) | Publish via shared memory (runs until Ctrl-C) |
| [`z_info.dart`](example/z_info.dart) | Print session ZID and connected router/peer ZIDs |
| [`z_scout.dart`](example/z_scout.dart) | Discover zenoh entities on the network |
| [`z_get.dart`](example/z_get.dart) | Send a query and receive replies |
| [`z_queryable.dart`](example/z_queryable.dart) | Declare a queryable that replies to queries |
| [`z_get_shm.dart`](example/z_get_shm.dart) | Send a query with SHM payload |
| [`z_queryable_shm.dart`](example/z_queryable_shm.dart) | Queryable that replies with SHM payloads |
| [`z_pull.dart`](example/z_pull.dart) | Pull subscriber with ring buffer (interactive polling) |
| [`z_querier.dart`](example/z_querier.dart) | Declared querier for repeated queries (runs until Ctrl-C) |

```bash
# Quick start examples
dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'
dart run example/z_sub.dart -k 'demo/example/**'
dart run example/z_get.dart -s 'demo/example/**'
dart run example/z_queryable.dart -k demo/example/zenoh-dart-queryable
dart run example/z_querier.dart -s 'demo/example/**'
dart run example/z_pull.dart -k 'demo/example/**' -s 3
```

## Platform Support

| Platform | Architecture | Status |
|----------|-------------|--------|
| Linux | x86_64 | Supported |
| Android | arm64-v8a, x86_64 | Supported |

## License

Apache 2.0 — see [LICENSE](LICENSE).
