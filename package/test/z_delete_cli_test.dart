import 'dart:io';

import 'package:test/test.dart';

void main() {
  // Get the package root (where pubspec.yaml lives)
  // Tests run from package/
  final packageRoot = Directory.current.path;

  group('z_delete CLI', () {
    Future<ProcessResult> runZDelete([List<String> args = const []]) async {
      return Process.run('fvm', [
        'dart',
        'run',
        'example/z_delete.dart',
        ...args,
      ], workingDirectory: packageRoot).timeout(const Duration(seconds: 30));
    }

    test('runs with default arguments', () async {
      final result = await runZDelete();
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('Deleting'));
    });

    test('accepts custom key', () async {
      final result = await runZDelete(['--key', 'demo/test']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('demo/test'));
    });

    test('with invalid key expression exits with error', () async {
      final result = await runZDelete(['--key', '']);
      expect(result.exitCode, isNot(0));
    });
  });
}
