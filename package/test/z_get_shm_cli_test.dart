import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;

  group('z_get_shm CLI', () {
    Future<ProcessResult> runZGetShm([List<String> args = const []]) async {
      return Process.run('fvm', [
        'dart',
        'run',
        'example/z_get_shm.dart',
        ...args,
      ], workingDirectory: packageRoot).timeout(const Duration(seconds: 30));
    }

    test('runs with default arguments and prints query', () async {
      final result = await runZGetShm(['--timeout', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('Sending Query'));
      expect(result.stdout as String, contains('demo/example/**'));
    });

    test('accepts --selector flag', () async {
      final result = await runZGetShm([
        '--selector',
        'demo/custom/**',
        '--timeout',
        '2000',
      ]);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('demo/custom/**'));
    });

    test('accepts short flags', () async {
      final result = await runZGetShm(['-s', 'demo/short/**', '-o', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('demo/short/**'));
    });

    test('prints SHM provider creation', () async {
      final result = await runZGetShm(['--timeout', '2000']);
      expect(result.exitCode, equals(0), reason: 'stderr: ${result.stderr}');
      expect(result.stdout as String, contains('SHM'));
    });
  });
}
