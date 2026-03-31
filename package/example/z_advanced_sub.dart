import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/**';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
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

  print("Declaring AdvancedSubscriber on '$keyExpr'...");
  final subscriber = session.declareAdvancedSubscriber(
    keyExpr,
    options: AdvancedSubscriberOptions(
      history: true,
      detectLatePublishers: true,
      recovery: true,
      lastSampleMissDetection: true,
      periodicQueriesPeriodMs: 1000,
      subscriberDetection: true,
      enableMissListener: true,
    ),
  );

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  // Listen for samples and print them
  final streamSubscription = subscriber.stream.listen((sample) {
    final kindStr = sample.kind == SampleKind.put ? 'PUT' : 'DELETE';
    print(
      ">> [Subscriber] Received $kindStr ('${sample.keyExpr}': "
      "'${sample.payload}')",
    );
  });

  // Listen for miss events if available
  StreamSubscription<MissEvent>? missSubscription;
  if (subscriber.missEvents != null) {
    missSubscription = subscriber.missEvents!.listen((event) {
      print(
        '>> [Subscriber] Missed ${event.count} samples from '
        "'${event.sourceId.toHexString()}'",
      );
    });
  }

  // Handle SIGINT and SIGTERM for clean shutdown
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;

  await sigintSub.cancel();
  await sigtermSub.cancel();
  await streamSubscription.cancel();
  await missSubscription?.cancel();
  subscriber.close();
  session.close();
}
