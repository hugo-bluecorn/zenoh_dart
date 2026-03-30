import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/**';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addFlag('complete', defaultsTo: false)
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final complete = results.flag('complete');
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

  // In-memory storage: key expression string -> Sample
  final storage = <String, Sample>{};

  print("Declaring Subscriber on '$keyExpr'...");
  final subscriber = session.declareSubscriber(keyExpr);

  print("Declaring Queryable on '$keyExpr'...");
  final queryable = session.declareQueryable(keyExpr, complete: complete);

  print('Press CTRL-C to quit...');

  final completer = Completer<void>();

  // Listen for samples and store/remove them
  final subStreamSub = subscriber.stream.listen((sample) {
    final kindStr = sample.kind == SampleKind.put ? 'PUT' : 'DELETE';
    print(
      ">> [Subscriber] Received $kindStr ('${sample.keyExpr}': "
      "'${sample.payload}')",
    );
    switch (sample.kind) {
      case SampleKind.put:
        storage[sample.keyExpr] = sample;
      case SampleKind.delete:
        storage.remove(sample.keyExpr);
    }
  });

  // Listen for queries and reply with matching stored entries
  final queryStreamSub = queryable.stream.listen((query) {
    print(
      ">> [Queryable ] Received Query '${query.keyExpr}' "
      "with parameters '${query.parameters}'",
    );

    final queryKe = KeyExpr(query.keyExpr);
    try {
      for (final entry in storage.entries) {
        final entryKe = KeyExpr(entry.key);
        try {
          if (entryKe.intersects(queryKe)) {
            query.reply(entry.key, entry.value.payload);
          }
        } finally {
          entryKe.dispose();
        }
      }
    } finally {
      queryKe.dispose();
    }
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
  await subStreamSub.cancel();
  await queryStreamSub.cancel();
  queryable.close();
  subscriber.close();
  session.close();
}
