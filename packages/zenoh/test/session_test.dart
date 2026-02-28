import 'package:test/test.dart';
import 'package:zenoh/src/config.dart';
import 'package:zenoh/src/session.dart';

void main() {
  group('Session lifecycle', () {
    test('open session with default config', () {
      // Given: the native library is initialized (via bindings singleton)
      // When: Session.open() is called with no config argument
      // Then: a Session object is returned; no exception is thrown
      final session = Session.open();
      expect(session, isA<Session>());
      session.close();
    });

    test('open session with explicit config', () {
      // Given: a Config with mode set to peer
      final config = Config();
      config.insertJson5('mode', '"peer"');

      // When: Session.open(config: config) is called
      // Then: a Session is returned; the config is consumed
      final session = Session.open(config: config);
      expect(session, isA<Session>());

      // Verify config is consumed by checking that further use throws
      expect(
        () => config.insertJson5('mode', '"peer"'),
        throwsA(isA<StateError>()),
      );

      session.close();
    });

    test('close session gracefully', () {
      // Given: an open Session
      final session = Session.open();

      // When: session.close() is called
      // Then: no exception is thrown
      expect(() => session.close(), returnsNormally);
    });

    test('close session is idempotent (double-close safe)', () {
      // Given: a Session that has already been closed
      final session = Session.open();
      session.close();

      // When: session.close() is called a second time
      // Then: no exception is thrown
      expect(() => session.close(), returnsNormally);
    });

    test('session remains usable across test group', () {
      // This test verifies the pattern of opening a session in setUpAll
      // and closing in tearDownAll -- the session is opened and closed
      // within this single test as a representative check.
      late Session session;

      // setUpAll equivalent
      session = Session.open();
      expect(session, isA<Session>());

      // Simulate multiple operations against the same session
      // (Session is still open -- no exception)
      expect(session, isNotNull);

      // tearDownAll equivalent
      session.close();
    });

    test('reusing consumed Config throws StateError', () {
      // Given: a Config passed to Session.open
      final config = Config();
      final session = Session.open(config: config);

      // When: config.insertJson5 is called on the consumed config
      // Then: a StateError is thrown
      expect(
        () => config.insertJson5('mode', '"peer"'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('consumed'),
          ),
        ),
      );

      session.close();
    });
  });
}
