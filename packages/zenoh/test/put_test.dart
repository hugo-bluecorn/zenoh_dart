import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('Session.put', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('put string on valid key expression succeeds', () {
      // Given: an open Session
      // When: session.put is called with a valid key and string value
      // Then: the call completes without throwing any exception
      expect(
        () => session.put('demo/example/test', 'Hello from Dart!'),
        returnsNormally,
      );
    });

    test('put empty string payload succeeds', () {
      // Given: an open Session
      // When: session.put is called with an empty string value
      // Then: the call completes without throwing any exception
      expect(
        () => session.put('demo/example/test', ''),
        returnsNormally,
      );
    });

    test('put with unicode payload succeeds', () {
      // Given: an open Session
      // When: session.put is called with a unicode string value
      // Then: the call completes without throwing any exception
      expect(
        () => session.put('demo/example/test', 'Hola Mundo!'),
        returnsNormally,
      );
    });

    test('put with invalid key expression throws ZenohException', () {
      // Given: an open Session
      // When: session.put is called with an empty key expression
      // Then: a ZenohException is thrown
      expect(
        () => session.put('', 'value'),
        throwsA(isA<ZenohException>()),
      );
    });

    test('put on closed session throws StateError', () {
      // Given: a Session that has been closed
      final closedSession = Session.open();
      closedSession.close();

      // When: session.put is called on the closed session
      // Then: a StateError is thrown with a message containing 'closed'
      expect(
        () => closedSession.put('demo/example/test', 'value'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });
  });

  group('Session.putBytes', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('putBytes with ZBytes payload succeeds', () {
      // Given: an open Session and a ZBytes payload
      final payload = ZBytes.fromString('test payload');

      // When: session.putBytes is called with a valid key and ZBytes payload
      // Then: the call completes without throwing any exception
      try {
        expect(
          () => session.putBytes('demo/example/test', payload),
          returnsNormally,
        );
      } finally {
        // payload may have been consumed; dispose is safe to call regardless
        payload.dispose();
      }
    });

    test('putBytes consumes the ZBytes payload', () {
      // Given: an open Session and a ZBytes payload
      final payload = ZBytes.fromString('consumed');

      // When: session.putBytes is called
      session.putBytes('demo/example/test', payload);

      // Then: subsequent payload.toStr() throws StateError (consumed)
      expect(
        () => payload.toStr(),
        throwsA(isA<StateError>()),
      );
    });

    test('putBytes with invalid key expression throws ZenohException', () {
      // Given: an open Session and a ZBytes payload
      final payload = ZBytes.fromString('value');

      // When: session.putBytes is called with an empty key expression
      // Then: a ZenohException is thrown
      try {
        expect(
          () => session.putBytes('', payload),
          throwsA(isA<ZenohException>()),
        );
      } finally {
        payload.dispose();
      }
    });

    test('putBytes on closed session throws StateError', () {
      // Given: a Session that has been closed and a ZBytes payload
      final closedSession = Session.open();
      closedSession.close();
      final payload = ZBytes.fromString('value');

      // When: session.putBytes is called on the closed session
      // Then: a StateError is thrown with a message containing 'closed'
      try {
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
      } finally {
        payload.dispose();
      }
    });

    test('putBytes with already-disposed ZBytes throws StateError', () {
      // Given: an open Session and a ZBytes that has been disposed
      final disposedPayload = ZBytes.fromString('gone');
      disposedPayload.dispose();

      // When: session.putBytes is called with the disposed ZBytes
      // Then: a StateError is thrown
      expect(
        () => session.putBytes('demo/example/test', disposedPayload),
        throwsA(isA<StateError>()),
      );
    });

    test('putBytes with invalid key expression does NOT consume the ZBytes',
        () {
      // Given: an open Session and a ZBytes payload
      final payload = ZBytes.fromString('still usable');

      // When: session.putBytes throws ZenohException due to invalid keyexpr
      expect(
        () => session.putBytes('', payload),
        throwsA(isA<ZenohException>()),
      );

      // Then: the ZBytes is still usable (was not consumed)
      expect(payload.toStr(), equals('still usable'));

      // Cleanup
      payload.dispose();
    });
  });
}
