import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/zenoh-dart-advanced-pub';
const defaultValue = 'Advanced Pub from Dart!';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('payload', abbr: 'p', defaultsTo: defaultValue)
    ..addOption('history', abbr: 'i', defaultsTo: '1')
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final value = results.option('payload')!;
  final history = int.parse(results.option('history')!);
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
  config.insertJson5('timestamping/enabled', 'true');
  final session = Session.open(config: config);

  print("Declaring AdvancedPublisher on '$keyExpr'...");
  final publisher = session.declareAdvancedPublisher(
    keyExpr,
    options: AdvancedPublisherOptions(
      cacheMaxSamples: history,
      publisherDetection: true,
      sampleMissDetection: true,
      heartbeatMode: HeartbeatMode.periodic,
      heartbeatPeriodMs: 500,
    ),
  );

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  var idx = 0;
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    final payload = '[$idx] $value';
    print("Putting Data ('$keyExpr': '$payload')...");
    publisher.put(payload);
    idx++;
  });

  await completer.future;

  timer.cancel();
  await sigintSub.cancel();
  await sigtermSub.cancel();
  publisher.close();
  session.close();
}
