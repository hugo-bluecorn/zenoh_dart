import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('no-express', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final noExpress = results.flag('no-express');
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

  print("Declaring Publisher on 'test/pong'...");
  final publisher = session.declarePublisher(
    'test/pong',
    isExpress: !noExpress,
  );

  print("Declaring Background Subscriber on 'test/ping'...");
  final bgStream = session.declareBackgroundSubscriber('test/ping');

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  final streamSubscription = bgStream.listen((sample) {
    final bytes = sample.payloadBytes;
    publisher.putBytes(ZBytes.fromUint8List(bytes));
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
  publisher.close();
  session.close();
}
