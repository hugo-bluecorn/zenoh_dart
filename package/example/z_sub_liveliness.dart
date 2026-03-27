import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'group1/**';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addFlag('history', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final history = results.flag('history');
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

  if (keyExpr.isEmpty) {
    stderr.writeln('Error: key expression must not be empty');
    exit(1);
  }

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

  print("Declaring Liveliness Subscriber on '$keyExpr'...");
  final subscriber = session.declareLivelinessSubscriber(
    keyExpr,
    history: history,
  );

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  final streamSubscription = subscriber.stream.listen((sample) {
    switch (sample.kind) {
      case SampleKind.put:
        print(
          ">> [LivelinessSubscriber] New alive token ('${sample.keyExpr}')",
        );
      case SampleKind.delete:
        print(">> [LivelinessSubscriber] Dropped token ('${sample.keyExpr}')");
    }
  });

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
  subscriber.close();
  session.close();
}
