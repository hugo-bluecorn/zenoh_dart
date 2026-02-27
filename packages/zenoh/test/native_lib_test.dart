import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:zenoh/src/exceptions.dart';
import 'package:zenoh/src/native_lib.dart';

void main() {
  group('Native library loading', () {
    test('loads successfully', () {
      // When the Dart native library loader is invoked
      // Then a DynamicLibrary instance is returned without throwing
      final lib = openZenohDartLibrary();
      expect(lib, isA<DynamicLibrary>());
    });
  });

  group('Dart API DL initialization', () {
    test('succeeds with return code 0', () {
      // Given the native library is loaded
      // When zd_init_dart_api_dl is called via the bindings singleton
      // Then the return code is 0 (success); return type is int
      final b = bindings;
      final result = b.zd_init_dart_api_dl(NativeApi.initializeApiDLData);
      expect(result, equals(0));
    });
  });

  group('zd_init_log', () {
    test('does not crash', () {
      // Given the native library is loaded and Dart API DL is initialized
      // (bindings singleton initializes Dart API DL on first access)
      // When zd_init_log is called with fallback filter "error"
      // Then the call completes without throwing (void return)
      expect(
        () => bindings.zd_init_log('error'.toNativeUtf8().cast()),
        returnsNormally,
      );
    });
  });

  group('ZenohException', () {
    test('carries message and return code', () {
      // Given a ZenohException constructed with message and return code
      final exception = ZenohException('test error', -1);

      // Then message and returnCode are accessible
      expect(exception.message, equals('test error'));
      expect(exception.returnCode, equals(-1));

      // And toString() contains both
      final str = exception.toString();
      expect(str, contains('test error'));
      expect(str, contains('-1'));
    });

    test('with zero return code formats correctly', () {
      // Given a ZenohException with return code 0
      final exception = ZenohException('zero code', 0);

      // When toString() is called
      final str = exception.toString();

      // Then it still formats correctly
      expect(str, contains('zero code'));
      expect(str, contains('0'));
    });
  });
}
