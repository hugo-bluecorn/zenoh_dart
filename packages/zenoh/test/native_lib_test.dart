import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:zenoh/src/bindings.dart' as ffi_bindings;
import 'package:zenoh/src/exceptions.dart';
import 'package:zenoh/src/native_lib.dart';

void main() {
  group('Native library loading', () {
    test('loads successfully via @Native resolution', () {
      // When a @Native function is called
      // Then the library resolves without throwing
      final size = ffi_bindings.zd_config_sizeof();
      expect(size, greaterThan(0));
    });
  });

  group('Dart API DL initialization', () {
    test('succeeds via ensureInitialized', () {
      // Given the native library is resolved via @Native
      // When ensureInitialized is called
      // Then it completes without throwing
      expect(() => ensureInitialized(), returnsNormally);
    });
  });

  group('zd_init_log', () {
    test('does not crash', () {
      // Given the native library is loaded and Dart API DL is initialized
      ensureInitialized();
      // When zd_init_log is called with fallback filter "error"
      // Then the call completes without throwing (void return)
      expect(
        () => ffi_bindings.zd_init_log('error'.toNativeUtf8().cast()),
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
