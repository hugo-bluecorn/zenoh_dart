import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/**';
const defaultSize = 256;

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('size', abbr: 's', defaultsTo: '$defaultSize')
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final size = int.parse(results.option('size')!);
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

  print(
    "Declaring Subscriber on '$keyExpr' with ring buffer capacity $size...",
  );
  final pullSubscriber = session.declarePullSubscriber(keyExpr, capacity: size);

  print("Press ENTER to pull data or 'q' to quit...");

  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line.trim() == 'q') break;

    // Pull all available samples from the ring buffer
    while (true) {
      final sample = pullSubscriber.tryRecv();
      if (sample == null) break;
      final kindStr = sample.kind == SampleKind.put ? 'PUT' : 'DELETE';
      print(
        ">> [Subscriber] Received $kindStr ('${sample.keyExpr}': "
        "'${sample.payload}')",
      );
    }
  }

  pullSubscriber.close();
  session.close();
}
