import 'dart:ffi';
import 'dart:io';
import 'dart:math' show max;

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultSharedMemorySize = 32; // MB

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption(
      'shared-memory',
      abbr: 's',
      defaultsTo: '$defaultSharedMemorySize',
    )
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);

  if (results.rest.isEmpty) {
    stderr.writeln('<PAYLOAD_SIZE> argument is required');
    exit(1);
  }

  final payloadSize = int.parse(results.rest[0]);
  final sharedMemorySizeMb = int.parse(results.option('shared-memory')!);
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

  Zenoh.initLog('error');

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

  print("Declaring Publisher on 'test/thr'...");
  final publisher = session.declarePublisher(
    'test/thr',
    congestionControl: CongestionControl.block,
  );

  final poolSize = max(sharedMemorySizeMb * 1024 * 1024, 65536);
  print('Creating SHM Provider ($sharedMemorySizeMb MB pool)...');
  final provider = ShmProvider(size: poolSize);

  print('Allocating SHM buffer ($payloadSize bytes)...');
  final buffer = provider.allocGcDefragBlocking(payloadSize);
  if (buffer == null) {
    stderr.writeln('Failed to allocate SHM buffer');
    publisher.close();
    provider.close();
    session.close();
    exit(1);
  }

  // Fill with 1 (memset pattern, matching C reference)
  final dataPtr = buffer.data;
  for (var i = 0; i < payloadSize; i++) {
    dataPtr[i] = 1;
  }

  // Convert to ZBytes once -- clone in the loop (zero-copy)
  final shmBytes = buffer.toBytes();

  print('Press CTRL-C to quit...');
  while (true) {
    publisher.putBytes(shmBytes.clone());
  }
}
