import 'dart:io';

import 'package:test/test.dart';

void main() {
  // Get the package root (where pubspec.yaml lives)
  // Tests run from packages/zenoh/
  final packageRoot = Directory.current.path;
  final repoRoot = '$packageRoot/../..';

  group('z_put CLI', () {
    Future<ProcessResult> runZPut([List<String> args = const []]) async {
      return Process.run(
        'fvm',
        ['dart', 'run', 'bin/z_put.dart', ...args],
        workingDirectory: packageRoot,
        environment: {
          ...Platform.environment,
          'LD_LIBRARY_PATH':
              '$repoRoot/extern/zenoh-c/target/release:$repoRoot/build',
        },
      ).timeout(const Duration(seconds: 30));
    }

    test('runs with default arguments', () async {
      final result = await runZPut();
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('Putting Data'));
    });

    test('accepts custom key and value', () async {
      final result = await runZPut([
        '--key',
        'demo/test',
        '--value',
        'Custom value',
      ]);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      final stdout = result.stdout as String;
      expect(stdout, contains('demo/test'));
      expect(stdout, contains('Custom value'));
    });

    test('with invalid key expression exits with error', () async {
      final result = await runZPut(['--key', '']);
      expect(result.exitCode, isNot(0));
    });
  });
}
