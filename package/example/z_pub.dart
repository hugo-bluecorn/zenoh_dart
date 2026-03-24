import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/zenoh-dart-pub';
const defaultValue = 'Pub from Dart!';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('payload', abbr: 'p', defaultsTo: defaultValue)
    ..addOption('attach', abbr: 'a')
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l')
    ..addFlag('add-matching-listener', defaultsTo: false);

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final value = results.option('payload')!;
  final attachStr = results.option('attach');
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');
  final addMatchingListener = results.flag('add-matching-listener');

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

  print("Declaring Publisher on '$keyExpr'...");
  final publisher = session.declarePublisher(
    keyExpr,
    enableMatchingListener: addMatchingListener,
  );

  if (addMatchingListener) {
    publisher.matchingStatus!.listen((matching) {
      if (matching) {
        print('Publisher has matching subscribers.');
      } else {
        print('Publisher has NO MORE matching subscribers.');
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
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    final payload = '[$idx] $value';
    print("Putting Data ('$keyExpr': '$payload')...");
    if (attachStr != null) {
      publisher.put(payload, attachment: ZBytes.fromString(attachStr));
    } else {
      publisher.put(payload);
    }
    idx++;
  });

  await completer.future;

  timer.cancel();
  await sigintSub.cancel();
  await sigtermSub.cancel();
  publisher.close();
  session.close();
}
