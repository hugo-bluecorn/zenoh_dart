import 'package:test/test.dart';
import 'package:zenoh/src/bytes.dart';
import 'package:zenoh/src/config.dart';
import 'package:zenoh/src/exceptions.dart';
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

  group('Put and delete operations', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('put succeeds with valid key expression', () {
      expect(() => session.put('demo/example/test', 'hello'), returnsNormally);
    });

    test('putBytes succeeds and consumes the payload', () {
      final payload = ZBytes.fromString('hello bytes');
      session.putBytes('demo/example/test', payload);
      // Payload should be consumed -- toStr() should throw
      expect(
        () => payload.toStr(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('consumed'),
          ),
        ),
      );
    });

    test('put with invalid key expression throws ZenohException', () {
      expect(() => session.put('', 'hello'), throwsA(isA<ZenohException>()));
    });

    test('putBytes with already-disposed ZBytes throws StateError', () {
      final payload = ZBytes.fromString('disposable');
      payload.dispose();
      expect(
        () => session.putBytes('demo/example/test', payload),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('putBytes with already-consumed ZBytes throws StateError', () {
      final payload = ZBytes.fromString('consume me');
      session.putBytes('demo/example/test', payload);
      expect(
        () => session.putBytes('demo/example/test', payload),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('consumed'),
          ),
        ),
      );
    });

    test('put on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.put('demo/example/test', 'hello'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('putBytes on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      final payload = ZBytes.fromString('hello');
      expect(
        () => closedSession.putBytes('demo/example/test', payload),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
      payload.dispose();
    });

    test('deleteResource succeeds with valid key expression', () {
      expect(
        () => session.deleteResource('demo/example/test'),
        returnsNormally,
      );
    });

    test('deleteResource on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.deleteResource('demo/example/test'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('deleteResource on non-existent key succeeds', () {
      // fire-and-forget semantics -- no error even if no data published
      expect(
        () => session.deleteResource('demo/example/nonexistent'),
        returnsNormally,
      );
    });

    test(
      'deleteResource with invalid key expression throws ZenohException',
      () {
        expect(
          () => session.deleteResource(''),
          throwsA(isA<ZenohException>()),
        );
      },
    );
  });
}
