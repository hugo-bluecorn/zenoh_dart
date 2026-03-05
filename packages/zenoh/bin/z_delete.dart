import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/zenoh-dart-put';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr);

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;

  Zenoh.initLog('error');

  print('Opening session...');
  final session = Session.open();

  print("Deleting resources matching '$keyExpr'...");
  session.deleteResource(keyExpr);

  session.close();
}
