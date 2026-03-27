import 'dart:io';

import 'package:test/test.dart';
// CLI tests for z_get_liveliness.dart

void main() {
  final packageRoot = Directory.current.path;

  group('z_get_liveliness CLI', () {
    Future<ProcessResult> runZGetLiveliness([
      List<String> args = const [],
    ]) async {
      return Process.run('fvm', [
        'dart',
        'run',
        'example/z_get_liveliness.dart',
        ...args,
      ], workingDirectory: packageRoot).timeout(const Duration(seconds: 30));
    }

    test('runs with default arguments and prints liveliness query', () async {
      final result = await runZGetLiveliness(['--timeout', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('Sending Liveliness Query'));
      expect(result.stdout as String, contains('group1/**'));
    });

    test('accepts custom key and timeout flags', () async {
      final result = await runZGetLiveliness([
        '-k',
        'custom/group/**',
        '-o',
        '2000',
      ]);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('custom/group/**'));
    });

    test('empty key expression exits with error', () async {
      final result = await runZGetLiveliness(['-k', '', '-o', '2000']);
      expect(result.exitCode, isNot(equals(0)));
    });
  });
}
