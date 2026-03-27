import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/zenoh-dart-queryable';
const defaultPayload = 'Queryable from Dart!';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('payload', abbr: 'p', defaultsTo: defaultPayload)
    ..addFlag('complete', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final payload = results.option('payload')!;
  final complete = results.flag('complete');
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

  print("Declaring Queryable on '$keyExpr'...");
  final queryable = session.declareQueryable(keyExpr, complete: complete);

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  // Listen for queries and reply to them
  final streamSubscription = queryable.stream.listen((query) {
    print(
      ">> [Queryable ] Received Query '${query.keyExpr}' "
      "with parameters '${query.parameters}'",
    );
    query.reply(keyExpr, payload);
    query.dispose();
  });

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
  queryable.close();
  session.close();
}
