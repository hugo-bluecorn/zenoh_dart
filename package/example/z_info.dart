import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
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

  final ownId = session.zid;
  print('own id: ${ownId.toHexString()}');

  print('routers ids:');
  for (final routerId in session.routersZid()) {
    print('  ${routerId.toHexString()}');
  }

  print('peers ids:');
  for (final peerId in session.peersZid()) {
    print('  ${peerId.toHexString()}');
  }

  session.close();
}
