import 'package:test/test.dart';
import 'package:zenoh/src/config.dart';
import 'package:zenoh/src/session.dart';

void main() {
  group('Session lifecycle', () {
    test('open session with default config', () {
      final session = Session.open();
      expect(session, isA<Session>());
      session.close();
    });

    test('open session with explicit config', () {
      final config = Config();
      config.insertJson5('mode', '"peer"');

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
      final session = Session.open();
      expect(() => session.close(), returnsNormally);
    });

    test('close session is idempotent (double-close safe)', () {
      final session = Session.open();
      session.close();
      expect(() => session.close(), returnsNormally);
    });

    test('reusing consumed Config throws StateError', () {
      final config = Config();
      final session = Session.open(config: config);

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

  group('Session operations', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('session remains usable across tests', () {
      // Session opened in setUpAll is still valid
      expect(session, isA<Session>());
    });
  });
}
