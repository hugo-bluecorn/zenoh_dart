import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' show max;

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

  final poolSize = max(payloadSize * 32, 65536);
  print('Creating SHM Provider (pool size: $poolSize bytes)...');
  final provider = ShmProvider(size: poolSize);

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

  // Allocate SHM buffer once, fill with payload pattern
  print('Allocating SHM buffer ($payloadSize bytes)...');
  final buffer = provider.allocGcDefragBlocking(payloadSize);
  if (buffer == null) {
    stderr.writeln('Failed to allocate SHM buffer');
    publisher.close();
    provider.close();
    session.close();
    exit(1);
  }

  final dataPtr = buffer.data;
  for (var i = 0; i < payloadSize; i++) {
    dataPtr[i] = i % 10;
  }

  // Convert to ZBytes once -- clone in the loop (zero-copy)
  final shmBytes = buffer.toBytes();

  // Warmup phase
  if (warmup > 0) {
    print('Warming up for ${warmup}ms...');
    final warmupStop = Stopwatch()..start();
    while (warmupStop.elapsedMilliseconds < warmup) {
      pongCompleter = Completer<void>();
      final cloned = shmBytes.clone();
      publisher.putBytes(cloned);
      await pongCompleter.future;
    }
    warmupStop.stop();
  }

  // Measurement phase
  for (var i = 0; i < samples; i++) {
    pongCompleter = Completer<void>();
    final stopwatch = Stopwatch()..start();
    final cloned = shmBytes.clone();
    publisher.putBytes(cloned);
    await pongCompleter.future;
    stopwatch.stop();
    final rtt = stopwatch.elapsedMicroseconds;
    final lat = rtt ~/ 2;
    print('$payloadSize bytes: seq=$i rtt=${rtt}us, lat=${lat}us');
  }

  await streamSubscription.cancel();
  shmBytes.dispose();
  buffer.dispose();
  publisher.close();
  provider.close();
  session.close();
}
