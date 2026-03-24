import 'dart:io';

import 'package:zenoh/zenoh.dart';

/// Helper script for inter-process pub/sub tests.
///
/// Modes:
///   `--mode sub --port PORT`  Listen on port, subscribe, print received samples
///   `--mode pub --port PORT`  Connect to port, publish payload
///
/// Options:
///   `--key KEY`       Key expression (default: interprocess/test)
///   `--payload TEXT`  Payload to publish (default: hello)
///   `--count N`       Number of messages to send/receive (default: 1)
void main(List<String> args) async {
  final modeIdx = args.indexOf('--mode');
  final mode = (modeIdx != -1 && modeIdx + 1 < args.length)
      ? args[modeIdx + 1]
      : null;
  final portIdx = args.indexOf('--port');
  final port = (portIdx != -1 && portIdx + 1 < args.length)
      ? args[portIdx + 1]
      : null;
  final keyIdx = args.indexOf('--key');
  final key = (keyIdx != -1 && keyIdx + 1 < args.length)
      ? args[keyIdx + 1]
      : 'interprocess/test';
  final payloadIdx = args.indexOf('--payload');
  final payload = (payloadIdx != -1 && payloadIdx + 1 < args.length)
      ? args[payloadIdx + 1]
      : 'hello';
  final countIdx = args.indexOf('--count');
  final count = (countIdx != -1 && countIdx + 1 < args.length)
      ? int.parse(args[countIdx + 1])
      : 1;

  if (mode == null || port == null) {
    stderr.writeln(
      'Usage: interprocess_pubsub.dart --mode pub|sub --port PORT '
      '[--key KEY] [--payload PAYLOAD] [--count N]',
    );
    exit(1);
  }

  final config = Config();
  config.insertJson5('mode', '"peer"');

  if (mode == 'sub') {
    config.insertJson5('listen/endpoints', '["tcp/127.0.0.1:$port"]');
    final session = Session.open(config: config);
    final subscriber = session.declareSubscriber(key);

    stdout.writeln('SUB_READY');

    var received = 0;
    await for (final sample in subscriber.stream) {
      stdout.writeln('RECEIVED:${sample.payload}');
      final bytes = sample.payloadBytes;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      stdout.writeln('BYTES:$hex');
      received++;
      if (received >= count) break;
    }

    subscriber.close();
    session.close();
    exit(0);
  } else if (mode == 'pub') {
    config.insertJson5('connect/endpoints', '["tcp/127.0.0.1:$port"]');
    final session = Session.open(config: config);

    stdout.writeln('PUB_READY');

    // Allow TCP link to establish
    await Future<void>.delayed(Duration(seconds: 1));

    for (var i = 0; i < count; i++) {
      final msg = count > 1 ? '$payload-$i' : payload;
      session.put(key, msg);
      stdout.writeln('SENT:$msg');
      if (i < count - 1) {
        await Future<void>.delayed(Duration(milliseconds: 200));
      }
    }

    // Allow messages to flush
    await Future<void>.delayed(Duration(seconds: 1));
    session.close();
    exit(0);
  } else {
    stderr.writeln('Unknown mode: $mode (expected pub or sub)');
    exit(1);
  }
}
