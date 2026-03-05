import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// The FVM-resolved Dart executable path.
const _dartExe = '/home/hugo-bluecorn/fvm/versions/stable/bin/dart';

/// Forcefully kills a process, using SIGKILL if SIGTERM doesn't work.
Future<void> forceKill(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 3));
  } catch (_) {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode
        .timeout(const Duration(seconds: 2))
        .catchError((_) => -1);
  }
}

void main() {
  final packageRoot = Directory.current.path;
  final repoRoot = '$packageRoot/../..';
  final ldLibraryPath =
      '$repoRoot/extern/zenoh-c/target/release:$repoRoot/build';

  Map<String, String> env() => {
    ...Platform.environment,
    'LD_LIBRARY_PATH': ldLibraryPath,
  };

  group('z_sub CLI', () {
    test('runs and prints subscriber declaration', () async {
      final process = await Process.start(
        _dartExe,
        ['run', 'bin/z_sub.dart'],
        workingDirectory: packageRoot,
        environment: env(),
      );

      final stdout = StringBuffer();
      final subscription = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen(stdout.write);

      // Let it run for 3 seconds, then kill it
      await Future<void>.delayed(const Duration(seconds: 3));
      await forceKill(process);
      await subscription.cancel();

      expect(stdout.toString(), contains('Declaring Subscriber'));
      expect(stdout.toString(), contains('demo/example/**'));
    });

    test('receives a sample from z_put', () async {
      // Use explicit TCP to ensure the two processes can communicate
      const port = 18551;
      const endpoint = 'tcp/127.0.0.1:$port';

      // Start z_sub listening on a specific key with TCP listener
      final subProcess = await Process.start(
        _dartExe,
        ['run', 'bin/z_sub.dart', '-k', 'demo/cli/test', '-l', endpoint],
        workingDirectory: packageRoot,
        environment: env(),
      );

      final subStdout = StringBuffer();
      final subSubscription = subProcess.stdout
          .transform(const SystemEncoding().decoder)
          .listen(subStdout.write);

      try {
        // Wait for subscriber session to bind TCP listener
        await Future<void>.delayed(const Duration(seconds: 5));

        // Run z_put connecting to the subscriber's TCP endpoint
        final putResult = await Process.run(
          _dartExe,
          [
            'run',
            'bin/z_put.dart',
            '-k',
            'demo/cli/test',
            '-p',
            'from-put',
            '-e',
            endpoint,
          ],
          workingDirectory: packageRoot,
          environment: env(),
        ).timeout(const Duration(seconds: 30));
        expect(
          putResult.exitCode,
          equals(0),
          reason: 'z_put stderr: ${putResult.stderr}',
        );

        // Wait for the sample to arrive
        await Future<void>.delayed(const Duration(seconds: 3));

        final output = subStdout.toString();
        expect(output, contains('Received PUT'));
        expect(output, contains('from-put'));
      } finally {
        await forceKill(subProcess);
        await subSubscription.cancel();
      }
    });

    test('accepts --key flag', () async {
      final process = await Process.start(
        _dartExe,
        ['run', 'bin/z_sub.dart', '--key', 'demo/custom/**'],
        workingDirectory: packageRoot,
        environment: env(),
      );

      final stdout = StringBuffer();
      final subscription = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen(stdout.write);

      await Future<void>.delayed(const Duration(seconds: 3));
      await forceKill(process);
      await subscription.cancel();

      expect(stdout.toString(), contains('demo/custom/**'));
    });

    test('with empty key expression fails', () async {
      final result = await Process.run(
        _dartExe,
        ['run', 'bin/z_sub.dart', '--key', ''],
        workingDirectory: packageRoot,
        environment: env(),
      ).timeout(const Duration(seconds: 30));

      expect(result.exitCode, isNot(0));
    });
  });
}
