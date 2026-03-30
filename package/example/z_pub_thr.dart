import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultPriority = 5; // Z_PRIORITY_DATA

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('priority', abbr: 'p', defaultsTo: '$defaultPriority')
    ..addFlag('express', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);

  if (results.rest.isEmpty) {
    stderr.writeln('<PAYLOAD_SIZE> argument is required');
    exit(1);
  }

  final payloadSize = int.parse(results.rest[0]);
  final priorityValue = int.parse(results.option('priority')!);
  final express = results.flag('express');
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
    priority: Priority.values[priorityValue - 1],
    isExpress: express,
  );

  // Build payload
  final data = Uint8List(payloadSize);
  for (var i = 0; i < payloadSize; i++) {
    data[i] = i % 10;
  }
  final zbytes = ZBytes.fromUint8List(data);

  print('Press CTRL-C to quit...');
  while (true) {
    publisher.putBytes(zbytes.clone());
  }
}
