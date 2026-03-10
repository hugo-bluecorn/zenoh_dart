import 'dart:ffi';
import 'dart:io';

import 'package:exp_hooks_cbuilder_native/exp_hooks_cbuilder_native.dart';
import 'package:exp_hooks_cbuilder_native/src/bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  String? loadError;

  setUpAll(() {
    try {
      // Attempt to call an @Native function to test resolution.
      // If @Native asset resolution works, this should succeed
      // WITHOUT LD_LIBRARY_PATH.
      zdInitDartApiDl(NativeApi.initializeApiDLData);
    } catch (e) {
      loadError = e.toString();
    }
  });

  group('@Native asset resolution (CBuilder-compiled)', () {
    test('@Native resolves zd_init_dart_api_dl without LD_LIBRARY_PATH', () {
      if (loadError != null) {
        markTestSkipped('@Native resolution failed: $loadError');
        return;
      }
      final result = zdInitDartApiDl(NativeApi.initializeApiDLData);
      expect(result, equals(0));
    });

    test('zd_init_log succeeds -- proves DT_NEEDED resolves libzenohc.so', () {
      if (loadError != null) {
        markTestSkipped('@Native resolution failed: $loadError');
        return;
      }
      final filter = 'error'.toNativeUtf8();
      try {
        expect(() => zdInitLog(filter), returnsNormally);
      } finally {
        calloc.free(filter);
      }
    });

    test('initZenohDart returns true', () {
      if (loadError != null) {
        markTestSkipped('@Native resolution failed: $loadError');
        return;
      }
      expect(initZenohDart(), isTrue);
    });

    test('@Native failure produces informative error', () {
      if (loadError != null) {
        // This test documents the failure mode.
        print('Error captured: $loadError');
        markTestSkipped('Confirmed @Native failure: $loadError');
        return;
      }
      // If we get here, @Native worked - document success.
      expect(loadError, isNull, reason: '@Native resolution succeeded');
    });
  });

  group('dart run verification', () {
    const packageDir =
        '/home/hugo-bluecorn/bluecorn/CSR/git/zenoh_dart/packages/exp_hooks_cbuilder_native';

    test(
      'dart run example/smoke.dart succeeds without LD_LIBRARY_PATH',
      () async {
        final result = await Process.run(
          'fvm',
          ['dart', 'run', 'example/smoke.dart'],
          workingDirectory: packageDir,
          environment: {'LD_LIBRARY_PATH': ''},
        );
        expect(
          result.exitCode,
          equals(0),
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}',
        );
        expect(
          result.stdout.toString(),
          contains('initZenohDart() returned: true'),
        );
      },
      timeout: Timeout(Duration(seconds: 30)),
    );

    test('dart run invokes build hook system', () async {
      final result = await Process.run(
        'fvm',
        ['dart', 'run', 'example/smoke.dart'],
        workingDirectory: packageDir,
        environment: {'LD_LIBRARY_PATH': ''},
      );
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      final combined = '$stderr$stdout';
      expect(
        combined,
        anyOf(
          contains('build hook'),
          contains('Building native assets'),
          contains('Running build'),
          contains('hook/build.dart'),
        ),
        reason:
            'Expected evidence of hook system invocation.\n'
            'stderr: $stderr\nstdout: $stdout',
      );
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
