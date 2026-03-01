import 'package:args/args.dart';
import 'package:zenoh/zenoh.dart';

const defaultKey = 'demo/example/zenoh-dart-put';
const defaultPayload = 'Put from Dart!';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('key', abbr: 'k', defaultsTo: defaultKey,
        help: 'The key expression to write to')
    ..addOption('payload', abbr: 'p', defaultsTo: defaultPayload,
        help: 'The value to write');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    print(e.message);
    print('Usage: z_put [OPTIONS]');
    print(parser.usage);
    return;
  }

  // Handle --help (package:args adds it automatically when we check)
  if (arguments.contains('--help') || arguments.contains('-h')) {
    print('Usage: z_put [OPTIONS]');
    print(parser.usage);
    return;
  }

  final key = args.option('key')!;
  final payload = args.option('payload')!;

  print('Opening session...');
  final session = Session.open();

  print("Putting Data ('$key': '$payload')...");
  session.put(key, payload);

  session.close();
}
