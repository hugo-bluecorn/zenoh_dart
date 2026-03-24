import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('connect', abbr: 'e')
    ..addMultiOption('listen', abbr: 'l');

  final results = parser.parse(arguments);
  final connectEndpoints = results.multiOption('connect');
  final listenEndpoints = results.multiOption('listen');

  Zenoh.initLog('error');

  final config = Config();
  if (connectEndpoints.isNotEmpty) {
    final json = '[${connectEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('connect/endpoints', json);
  }
  if (listenEndpoints.isNotEmpty) {
    final json = '[${listenEndpoints.map((e) => '"$e"').join(',')}]';
    config.insertJson5('listen/endpoints', json);
  }

  print('Scouting...');
  final hellos = await Zenoh.scout(config: config);

  if (hellos.isEmpty) {
    print('Did not find any zenoh process.');
  } else {
    for (final hello in hellos) {
      print(hello);
    }
  }
}
