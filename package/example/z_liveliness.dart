import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'group1/zenoh-dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
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

  final token = session.declareLivelinessToken(keyExpr);
  print("Liveliness token declared on '$keyExpr'");
  print('Press CTRL-C to undeclare token and quit...');

  final completer = Completer<void>();

  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;

  await sigintSub.cancel();
  await sigtermSub.cancel();
  token.close();
  session.close();
}
