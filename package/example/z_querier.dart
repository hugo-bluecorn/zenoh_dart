import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultSelector = 'demo/example/**';
const defaultTimeoutMs = 10000;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('selector', abbr: 's', defaultsTo: defaultSelector)
    ..addOption('payload', abbr: 'p')
    ..addOption('target', abbr: 't', defaultsTo: 'BEST_MATCHING')
    ..addOption('timeout', abbr: 'o', defaultsTo: '$defaultTimeoutMs')
    ..addFlag('add-matching-listener', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final selector = results.option('selector')!;
  final payloadStr = results.option('payload');
  final targetStr = results.option('target')!;
  final timeoutMs = int.parse(results.option('timeout')!);
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');
  final addMatchingListener = results.flag('add-matching-listener');

  final target = switch (targetStr) {
    'ALL' => QueryTarget.all,
    'ALL_COMPLETE' => QueryTarget.allComplete,
    _ => QueryTarget.bestMatching,
  };

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

  // Split selector at '?' into key expression and parameters
  String keyExpr = selector;
  String? parameters;
  final qIndex = selector.indexOf('?');
  if (qIndex >= 0) {
    keyExpr = selector.substring(0, qIndex);
    parameters = selector.substring(qIndex + 1);
  }

  print("Declaring Querier on '$keyExpr'...");
  final querier = session.declareQuerier(
    keyExpr,
    target: target,
    timeout: Duration(milliseconds: timeoutMs),
    enableMatchingListener: addMatchingListener,
  );

  if (addMatchingListener) {
    querier.matchingStatus!.listen((matching) {
      if (matching) {
        print('Querier has matching queryables.');
      } else {
        print('Querier has NO MORE matching queryables.');
      }
    });
  }

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });
  final sigtermSub = ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  var idx = 0;
  final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
    final buf = '[$idx] ${payloadStr ?? ''}';
    print("Querying '$selector' with payload '$buf'...");

    final zbytes = payloadStr != null ? ZBytes.fromString(buf) : null;

    final stream = querier.get(payload: zbytes, parameters: parameters);

    await for (final reply in stream) {
      if (reply.isOk) {
        print(">> Received ('${reply.ok.keyExpr}': '${reply.ok.payload}')");
      } else {
        print(">> Received (ERROR: '${reply.error.payload}')");
      }
    }

    idx++;
  });

  await completer.future;

  timer.cancel();
  await sigintSub.cancel();
  await sigtermSub.cancel();
  querier.close();
  session.close();
}
