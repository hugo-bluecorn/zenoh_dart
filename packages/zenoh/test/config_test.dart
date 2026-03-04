import 'package:test/test.dart';
import 'package:zenoh/src/config.dart';
import 'package:zenoh/src/exceptions.dart';
import 'package:zenoh/src/session.dart';

void main() {
  group('Config lifecycle', () {
    test('default config creation succeeds', () {
      // Given: the native library is initialized (via bindings singleton)
      // When: Config() is constructed
      // Then: no exception is thrown; the Config object is created successfully
      final config = Config();
      expect(config, isA<Config>());
      config.dispose();
    });

    test('insertJson5 with valid key-value succeeds', () {
      // Given: a default Config
      final config = Config();

      // When: insertJson5 is called with a valid key and JSON5 value
      // Then: no exception is thrown
      expect(() => config.insertJson5('mode', '"peer"'), returnsNormally);

      config.dispose();
    });

    test('dispose releases resources', () {
      // Given: a Config object
      final config = Config();

      // When: config.dispose() is called
      // Then: no exception is thrown
      expect(() => config.dispose(), returnsNormally);
    });

    test('dispose is idempotent (double-drop safe)', () {
      // Given: a Config that has already been disposed
      final config = Config();
      config.dispose();

      // When: config.dispose() is called a second time
      // Then: no exception is thrown
      expect(() => config.dispose(), returnsNormally);
    });

    test('insertJson5 with invalid key throws ZenohException', () {
      // Given: a default Config
      final config = Config();

      // When: insertJson5 is called with an invalid key
      // Then: a ZenohException is thrown with a negative return code
      expect(
        () => config.insertJson5('nonexistent/garbage/key', '"value"'),
        throwsA(
          isA<ZenohException>().having(
            (e) => e.returnCode,
            'returnCode',
            isNegative,
          ),
        ),
      );

      config.dispose();
    });

    test('insertJson5 after dispose throws StateError', () {
      final config = Config();
      config.dispose();
      expect(() => config.insertJson5('mode', '"peer"'), throwsStateError);
    });

    test('insertJson5 with invalid JSON5 value throws ZenohException', () {
      final config = Config();
      // 'peer' without quotes is invalid JSON5 for a string field
      expect(
        () => config.insertJson5('mode', 'not_valid_json5'),
        throwsA(isA<ZenohException>()),
      );
      config.dispose();
    });

    test('insertJson5 after consumed throws StateError', () {
      final config = Config();
      final session = Session.open(config: config);
      expect(() => config.insertJson5('mode', '"peer"'), throwsStateError);
      session.close();
    });
  });
}
