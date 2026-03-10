import 'dart:ffi';
import 'dart:io';

import 'package:exp_hooks_cbuilder_dlopen/exp_hooks_cbuilder_dlopen.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  DynamicLibrary? lib;
  String? loadError;

  setUpAll(() {
    try {
      lib = DynamicLibrary.open('libzenoh_dart.so');
    } on ArgumentError catch (e) {
      loadError = e.message.toString();
    }
  });

  group('DynamicLibrary.open() with CBuilder-compiled library', () {
    test(
      'finds CBuilder-compiled libzenoh_dart.so without LD_LIBRARY_PATH',
      () {
        if (loadError != null) {
          markTestSkipped(
            'DynamicLibrary.open cannot find CBuilder output: $loadError',
          );
          return;
        }
        expect(lib, isNotNull);
      },
    );

    test(
      'zd_init_dart_api_dl succeeds -- proves CBuilder-compiled shim loaded',
      () {
        if (lib == null) {
          markTestSkipped(
            'DynamicLibrary.open failed, cannot test FFI: $loadError',
          );
          return;
        }

        final initDartApiDl = lib!
            .lookupFunction<
              IntPtr Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('zd_init_dart_api_dl');

        final result = initDartApiDl(NativeApi.initializeApiDLData);
        expect(
          result,
          equals(0),
          reason: 'zd_init_dart_api_dl should return 0',
        );
      },
    );

    test(
      'zd_init_log succeeds -- proves libzenohc.so resolved via DT_NEEDED',
      () {
        if (lib == null) {
          markTestSkipped(
            'DynamicLibrary.open failed, cannot test FFI: $loadError',
          );
          return;
        }

        final initLog = lib!
            .lookupFunction<
              Void Function(Pointer<Utf8>),
              void Function(Pointer<Utf8>)
            >('zd_init_log');

        final level = 'error'.toNativeUtf8();
        try {
          // Should complete without throwing.
          initLog(level);
        } finally {
          calloc.free(level);
        }
      },
    );

    test('initZenohDart returns true -- end-to-end validation', () {
      if (loadError != null) {
        markTestSkipped(
          'DynamicLibrary.open cannot find CBuilder output: $loadError',
        );
        return;
      }
      expect(initZenohDart(), isTrue);
    });

    test('DynamicLibrary.open failure produces informative error message', () {
      if (loadError != null) {
        // Negative result captured -- record the error message.
        expect(
          loadError,
          isNotEmpty,
          reason: 'Error message should be informative',
        );
        expect(
          loadError,
          contains('libzenoh_dart.so'),
          reason: 'Error should mention the library name',
        );
        markTestSkipped(
          'Confirmed: DynamicLibrary.open fails with: $loadError',
        );
        return;
      }
      // Positive result -- the library loaded fine.
      expect(lib, isNotNull);
    });
  });

  group('dart run verification', () {
    final packageDir =
        '/home/hugo-bluecorn/bluecorn/CSR/git/zenoh_dart/packages/exp_hooks_cbuilder_dlopen';

    test('dart run invokes build hook system', () async {
      final result = await Process.run(
        'fvm',
        ['dart', 'run', 'example/smoke.dart'],
        workingDirectory: packageDir,
        environment: {'LD_LIBRARY_PATH': ''},
      );
      final combined = '${result.stdout}${result.stderr}'.toLowerCase();
      expect(
        combined,
        anyOf(contains('build'), contains('hook'), contains('compil')),
        reason:
            'stdout+stderr should show evidence of build hook invocation.\n'
            'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }, timeout: Timeout(Duration(seconds: 30)));

    test('dart run outcome matches DynamicLibrary.open result', () async {
      final result = await Process.run(
        'fvm',
        ['dart', 'run', 'example/smoke.dart'],
        workingDirectory: packageDir,
        environment: {'LD_LIBRARY_PATH': ''},
      );
      if (result.exitCode != 0) {
        // Negative result: DynamicLibrary.open fails without LD_LIBRARY_PATH.
        final combined = '${result.stdout}${result.stderr}';
        expect(
          combined,
          contains('libzenoh_dart.so'),
          reason: 'Error output should mention the library name',
        );
      } else {
        // Positive result: library loaded successfully.
        expect(
          result.stdout.toString(),
          contains('initZenohDart() returned: true'),
        );
      }
    }, timeout: Timeout(Duration(seconds: 30)));

    test('dart run with LD_LIBRARY_PATH as control', () async {
      final cbuilderOutput = '$packageDir/.dart_tool/lib';
      final nativeDir = '$packageDir/native/linux/x86_64';
      final result = await Process.run(
        'fvm',
        ['dart', 'run', 'example/smoke.dart'],
        workingDirectory: packageDir,
        environment: {'LD_LIBRARY_PATH': '$cbuilderOutput:$nativeDir'},
      );
      expect(
        result.exitCode,
        equals(0),
        reason: 'stderr: ${result.stderr}',
      );
      expect(
        result.stdout.toString(),
        contains('initZenohDart() returned: true'),
      );
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
