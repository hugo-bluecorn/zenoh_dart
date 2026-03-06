import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('Publisher lifecycle', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('declarePublisher returns a Publisher on valid key expression', () {
      final publisher = session.declarePublisher('demo/example/pub');
      expect(publisher, isA<Publisher>());
      publisher.close();
    });

    test('Publisher.keyExpr returns the declared key expression', () {
      final publisher = session.declarePublisher('demo/example/pub');
      expect(publisher.keyExpr, equals('demo/example/pub'));
      publisher.close();
    });

    test('Publisher.close completes without error', () {
      final publisher = session.declarePublisher('demo/example/pub');
      expect(() => publisher.close(), returnsNormally);
    });

    test('Publisher.close is idempotent (double-close safe)', () {
      final publisher = session.declarePublisher('demo/example/pub');
      publisher.close();
      expect(() => publisher.close(), returnsNormally);
    });

    test('declarePublisher on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.declarePublisher('demo/example/pub'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test(
      'declarePublisher with invalid key expression throws ZenohException',
      () {
        expect(
          () => session.declarePublisher(''),
          throwsA(isA<ZenohException>()),
        );
      },
    );

    test('Publisher operations after close throw StateError', () {
      final publisher = session.declarePublisher('demo/example/pub');
      publisher.close();

      expect(
        () => publisher.put('test'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => publisher.putBytes(ZBytes.fromString('test')),
        throwsA(isA<StateError>()),
      );
      expect(
        () => publisher.deleteResource(),
        throwsA(isA<StateError>()),
      );
      expect(
        () => publisher.keyExpr,
        throwsA(isA<StateError>()),
      );
      expect(
        () => publisher.hasMatchingSubscribers(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
