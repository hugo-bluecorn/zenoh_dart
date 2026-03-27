import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'group1/**';
const defaultTimeoutMs = 10000;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('timeout', abbr: 'o', defaultsTo: '$defaultTimeoutMs')
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final timeoutMs = int.parse(results.option('timeout')!);
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

  // Validate key expression before opening session (matches C reference).
  try {
    final ke = KeyExpr(keyExpr);
    ke.dispose();
  } on ZenohException {
    stderr.writeln('$keyExpr is not a valid key expression');
    exit(1);
  }

  final session = Session.open(config: config);

  print("Sending Liveliness Query '$keyExpr'...");

  try {
    final stream = session.livelinessGet(
      keyExpr,
      timeout: Duration(milliseconds: timeoutMs),
    );

    await for (final reply in stream) {
      if (reply.isOk) {
        print(">> Alive token ('${reply.ok.keyExpr}')");
      } else {
        print('>> Received an error');
      }
    }
  } on ZenohException catch (e) {
    stderr.writeln('Error: $e');
    session.close();
    exit(1);
  }

  session.close();
}
