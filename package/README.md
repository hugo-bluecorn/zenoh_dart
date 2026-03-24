# zenoh

Pure Dart FFI bindings for the [Zenoh](https://zenoh.io/) pub/sub/query protocol.

## Features

- Peer-to-peer and routed communication via zenoh
- Publish/subscribe with key expressions
- Shared memory (SHM) zero-copy publishing (Linux)
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
| `Session` | Open/close sessions; put, subscribe, publish, query info |
| `KeyExpr` | Key expression creation and validation |
| `ZBytes` | Binary payload container |
| `Publisher` | Declared publisher with put/delete/matching status |
| `Subscriber` | Callback-based subscriber delivering `Stream<Sample>` |
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

All examples support `-e`/`--connect` and `-l`/`--listen` flags for endpoint configuration.

```bash
# Put data on a key expression
dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'

# Delete a key expression
dart run example/z_delete.dart -k demo/example/test

# Subscribe to a key expression (runs until Ctrl-C)
dart run example/z_sub.dart -k 'demo/example/**'

# Publish in a loop (runs until Ctrl-C)
dart run example/z_pub.dart -k demo/example/test -p 'Hello from Dart!'

# Publish via shared memory in a loop (runs until Ctrl-C)
dart run example/z_pub_shm.dart -k demo/example/test -p 'Hello from SHM!'

# Print own session ZID and connected router/peer ZIDs
dart run example/z_info.dart

# Discover zenoh entities on the network
dart run example/z_scout.dart
```

## Platform Support

| Platform | Architecture | Status |
|----------|-------------|--------|
| Linux | x86_64 | Supported |
| Android | arm64-v8a, x86_64 | Supported |

## License

Apache 2.0 — see [LICENSE](LICENSE).
