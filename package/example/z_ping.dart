import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultSamples = 100;
const defaultWarmup = 1000;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('samples', abbr: 'n', defaultsTo: '$defaultSamples')
    ..addOption('warmup', abbr: 'w', defaultsTo: '$defaultWarmup')
    ..addFlag('no-express', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);

  if (results.rest.isEmpty) {
    stderr.writeln('<PAYLOAD_SIZE> argument is required');
    exit(1);
  }

  final payloadSize = int.parse(results.rest[0]);
  final samples = int.parse(results.option('samples')!);
  final warmup = int.parse(results.option('warmup')!);
  final noExpress = results.flag('no-express');
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

  Zenoh.initLog('info');

  print('Opening session...');
  final config = Config();
  if (connectEndpoints.isNotEmpty) {
    final json = '[${connectEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('connect/endpoints', json);
  }
  if (listenEndpoints.isNotEmpty) {
    final json = '[${listenEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('listen/endpoints', json);
  }
  final session = Session.open(config: config);

  print("Declaring Publisher on 'test/ping'...");
  final publisher = session.declarePublisher(
    'test/ping',
    isExpress: !noExpress,
  );

  print("Declaring Background Subscriber on 'test/pong'...");
  final bgStream = session.declareBackgroundSubscriber('test/pong');

  var pongCompleter = Completer<void>();
  final streamSubscription = bgStream.listen((_) {
    if (!pongCompleter.isCompleted) pongCompleter.complete();
  });

  // Build payload
  final payload = Uint8List(payloadSize);
  for (var i = 0; i < payloadSize; i++) {
    payload[i] = i % 10;
  }

  // Warmup phase
  if (warmup > 0) {
    print('Warming up for ${warmup}ms...');
    final warmupStop = Stopwatch()..start();
    while (warmupStop.elapsedMilliseconds < warmup) {
      pongCompleter = Completer<void>();
      publisher.putBytes(ZBytes.fromUint8List(payload));
      await pongCompleter.future;
    }
    warmupStop.stop();
  }

  // Measurement phase
  for (var i = 0; i < samples; i++) {
    pongCompleter = Completer<void>();
    final stopwatch = Stopwatch()..start();
    publisher.putBytes(ZBytes.fromUint8List(payload));
    await pongCompleter.future;
    stopwatch.stop();
    final rtt = stopwatch.elapsedMicroseconds;
    final lat = rtt ~/ 2;
    print('$payloadSize bytes: seq=$i rtt=${rtt}us, lat=${lat}us');
  }

  await streamSubscription.cancel();
  publisher.close();
  session.close();
}
