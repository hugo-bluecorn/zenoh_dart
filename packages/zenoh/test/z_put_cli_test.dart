import 'dart:io';

import 'package:test/test.dart';

void main() {
  final projectRoot = Directory.current.path.endsWith('packages/zenoh')
      ? Directory.current.path
      : '${Directory.current.path}/packages/zenoh';

  // Resolve to absolute monorepo root for LD_LIBRARY_PATH
  final monorepoRoot = Directory(projectRoot).parent.parent.path;
  final ldLibraryPath =
      '$monorepoRoot/extern/zenoh-c/target/release:$monorepoRoot/build';

  /// Runs the z_put CLI with [args] and returns the process result.
  Future<ProcessResult> runZPut([List<String> args = const []]) {
    return Process.run(
      'fvm',
      ['dart', 'run', 'bin/z_put.dart', ...args],
      workingDirectory: projectRoot,
      environment: {'LD_LIBRARY_PATH': ldLibraryPath},
    ).timeout(const Duration(seconds: 30));
  }

  group('z_put CLI', () {
    test('runs with default arguments and prints confirmation', () async {
      final result = await runZPut();

      expect(result.exitCode, equals(0),
          reason: 'stderr: ${result.stderr}');
      final stdout = result.stdout as String;
      expect(stdout, contains('Putting Data'));
      expect(stdout, contains('demo/example/zenoh-dart-put'));
    });

    test('accepts custom key and payload arguments', () async {
      final result =
          await runZPut(['-k', 'demo/custom/key', '-p', 'Custom value']);

      expect(result.exitCode, equals(0),
          reason: 'stderr: ${result.stderr}');
      final stdout = result.stdout as String;
      expect(stdout, contains('demo/custom/key'));
      expect(stdout, contains('Custom value'));
    });

    test('--help shows usage information', () async {
      final result = await runZPut(['--help']);

      expect(result.exitCode, equals(0),
          reason: 'stderr: ${result.stderr}');
      final stdout = result.stdout as String;
      expect(stdout, contains('-k'));
      expect(stdout, contains('-p'));
    });
  });
}
