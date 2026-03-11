import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:zenoh/src/bindings.dart' as ffi_bindings;
import 'package:zenoh/src/native_lib.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ensureInitialized with DynamicLibrary.open pre-load', () {
    test('completes without error', () {
      expect(() => ensureInitialized(), returnsNormally);
    });

    test('is idempotent', () {
      ensureInitialized();
      expect(() => ensureInitialized(), returnsNormally);
    });

    test('@Native functions resolve after pre-load', () {
      ensureInitialized();
      final size = ffi_bindings.zd_config_sizeof();
      expect(size, greaterThan(0));
    });

    test('zd_init_log does not crash after pre-load', () {
      ensureInitialized();
      expect(
        () => ffi_bindings.zd_init_log('error'.toNativeUtf8().cast()),
        returnsNormally,
      );
    });

    test('Session.open works after pre-load change', () {
      final session = Session.open();
      expect(session, isNotNull);
      session.close();
    });
  });

  group('ZenohException', () {
    test('carries message and return code', () {
      final exception = ZenohException('test error', -1);
      expect(exception.message, equals('test error'));
      expect(exception.returnCode, equals(-1));
      final str = exception.toString();
      expect(str, contains('test error'));
      expect(str, contains('-1'));
    });
  });
}
