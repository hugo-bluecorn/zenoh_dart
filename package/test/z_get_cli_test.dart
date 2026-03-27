import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;

  group('z_get CLI', () {
    Future<ProcessResult> runZGet([List<String> args = const []]) async {
      return Process.run('fvm', [
        'dart',
        'run',
        'example/z_get.dart',
        ...args,
      ], workingDirectory: packageRoot).timeout(const Duration(seconds: 30));
    }

    test('runs with default arguments and prints query', () async {
      final result = await runZGet(['--timeout', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('Sending Query'));
      expect(result.stdout as String, contains('demo/example/**'));
    });

    test('accepts --selector flag', () async {
      final result = await runZGet([
        '--selector',
        'demo/custom/**',
        '--timeout',
        '2000',
      ]);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('demo/custom/**'));
    });

    test('accepts short flags', () async {
      final result = await runZGet(['-s', 'demo/short/**', '-o', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('demo/short/**'));
    });
  });
}
