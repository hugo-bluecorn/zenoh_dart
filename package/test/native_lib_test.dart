import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:zenoh/src/native_lib.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ensureInitialized with DynamicLibrary.open', () {
    test('completes without error', () {
      expect(() => ensureInitialized(), returnsNormally);
    });

    test('is idempotent', () {
      ensureInitialized();
      expect(() => ensureInitialized(), returnsNormally);
    });

    test('bindings resolve after initialization', () {
      ensureInitialized();
      final size = bindings.zd_config_sizeof();
      expect(size, greaterThan(0));
    });

    test('zd_init_log does not crash', () {
      ensureInitialized();
      expect(
        () => bindings.zd_init_log('error'.toNativeUtf8().cast()),
        returnsNormally,
      );
    });

    test('Session.open works', () {
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
