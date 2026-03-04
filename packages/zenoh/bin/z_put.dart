import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKeyExpr = 'demo/example/zenoh-dart-put';
const defaultValue = 'Put from Dart!';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKeyExpr)
    ..addOption('payload', abbr: 'p', defaultsTo: defaultValue);

  final results = parser.parse(arguments);
  final keyExpr = results.option('key')!;
  final value = results.option('payload')!;

  print('Opening session...');
  final session = Session.open();

  print("Putting Data ('$keyExpr': '$value')...");
  session.put(keyExpr, value);

  session.close();
}
