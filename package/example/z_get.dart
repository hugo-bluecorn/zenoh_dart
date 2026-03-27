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
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final selector = results.option('selector')!;
  final payloadStr = results.option('payload');
  final targetStr = results.option('target')!;
  final timeoutMs = int.parse(results.option('timeout')!);
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

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

  print("Sending Query '$selector'...");

  final zbytes = payloadStr != null
      ? ZBytes.fromString(payloadStr)
      : null;

  final stream = session.get(
    selector,
    payload: zbytes,
    target: target,
    timeout: Duration(milliseconds: timeoutMs),
  );

  await for (final reply in stream) {
    if (reply.isOk) {
      print(">> Received ('${reply.ok.keyExpr}': '${reply.ok.payload}')");
    } else {
      print(">> Received (ERROR: '${reply.error.payload}')");
    }
  }

  session.close();
}
