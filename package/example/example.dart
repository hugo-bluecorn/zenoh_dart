import 'package:zenoh/zenoh.dart';

void main() {
  Zenoh.initLog('error');

  // Open a zenoh session in peer mode (default)
  final session = Session.open();

  // Put a value on a key expression
  session.put('demo/example/greeting', 'Hello from Dart!');

  // Delete a resource
  session.deleteResource('demo/example/greeting');

  session.close();
}
