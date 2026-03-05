import 'dart:async';

import 'package:test/test.dart';
import 'package:zenoh/src/config.dart';
import 'package:zenoh/src/exceptions.dart';
import 'package:zenoh/src/sample.dart';
import 'package:zenoh/src/session.dart';
import 'package:zenoh/src/subscriber.dart';

void main() {
  group('SampleKind', () {
    test('has put and delete values that are distinct', () {
      expect(SampleKind.put, isNotNull);
      expect(SampleKind.delete, isNotNull);
      expect(SampleKind.put, isNot(equals(SampleKind.delete)));
    });
  });

  group('Sample', () {
    test('roundtrips all fields including nullable attachment', () {
      final sample = Sample(
        keyExpr: 'demo/test',
        payload: 'hello',
        kind: SampleKind.put,
        attachment: 'metadata',
      );
      expect(sample.keyExpr, equals('demo/test'));
      expect(sample.payload, equals('hello'));
      expect(sample.kind, equals(SampleKind.put));
      expect(sample.attachment, equals('metadata'));

      final sampleNoAttachment = Sample(
        keyExpr: 'demo/test',
        payload: 'hello',
        kind: SampleKind.put,
      );
      expect(sampleNoAttachment.attachment, isNull);
    });
  });

  group('Subscriber lifecycle', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('declareSubscriber returns a Subscriber on valid key expression', () {
      final subscriber = session.declareSubscriber('demo/example/test');
      expect(subscriber, isA<Subscriber>());
      subscriber.close();
    });

    test('Subscriber.close completes without error', () {
      final subscriber = session.declareSubscriber('demo/example/test');
      expect(() => subscriber.close(), returnsNormally);
    });

    test('Subscriber.close is idempotent (double-close safe)', () {
      final subscriber = session.declareSubscriber('demo/example/test');
      subscriber.close();
      expect(() => subscriber.close(), returnsNormally);
    });

    test('declareSubscriber on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.declareSubscriber('demo/example/test'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('declareSubscriber with invalid key expression throws ZenohException',
        () {
      expect(
        () => session.declareSubscriber(''),
        throwsA(isA<ZenohException>()),
      );
    });
  });

  group('Subscriber integration (NativePort bridge)', () {
    late Session session1;
    late Session session2;

    setUpAll(() async {
      // Sessions must be explicitly connected via TCP for same-process
      // peer-to-peer routing (multicast scouting doesn't work within
      // a single process).
      final config1 = Config();
      config1.insertJson5(
        'listen/endpoints',
        '["tcp/127.0.0.1:17448"]',
      );
      session1 = Session.open(config: config1);

      // Small delay to let session1's listener bind
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final config2 = Config();
      config2.insertJson5(
        'connect/endpoints',
        '["tcp/127.0.0.1:17448"]',
      );
      session2 = Session.open(config: config2);

      // Allow session link establishment
      await Future<void>.delayed(const Duration(seconds: 1));
    });

    tearDownAll(() {
      session1.close();
      session2.close();
    });

    test('receives PUT sample from session.put on same key', () async {
      final subscriber =
          session2.declareSubscriber('zenoh/dart/test/sub');
      addTearDown(subscriber.close);

      // Allow routing propagation
      await Future<void>.delayed(const Duration(seconds: 1));

      session1.put('zenoh/dart/test/sub', 'hello world');

      final sample = await subscriber.stream
          .first
          .timeout(const Duration(seconds: 5));

      expect(sample.keyExpr, equals('zenoh/dart/test/sub'));
      expect(sample.payload, equals('hello world'));
      expect(sample.kind, equals(SampleKind.put));
    });

    test('receives multiple PUT samples in order', () async {
      final subscriber =
          session2.declareSubscriber('zenoh/dart/test/multi');
      addTearDown(subscriber.close);

      await Future<void>.delayed(const Duration(seconds: 1));

      session1.put('zenoh/dart/test/multi', 'first');
      session1.put('zenoh/dart/test/multi', 'second');
      session1.put('zenoh/dart/test/multi', 'third');

      final samples = await subscriber.stream
          .take(3)
          .toList()
          .timeout(const Duration(seconds: 5));

      expect(samples, hasLength(3));
      expect(samples[0].payload, equals('first'));
      expect(samples[1].payload, equals('second'));
      expect(samples[2].payload, equals('third'));
    });

    test('receives samples matching wildcard key expression', () async {
      final subscriber =
          session2.declareSubscriber('zenoh/dart/test/wild/**');
      addTearDown(subscriber.close);

      await Future<void>.delayed(const Duration(seconds: 1));

      session1.put('zenoh/dart/test/wild/a', 'alpha');
      session1.put('zenoh/dart/test/wild/b', 'beta');

      final samples = await subscriber.stream
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 5));

      expect(samples, hasLength(2));
      final keyExprs = samples.map((s) => s.keyExpr).toSet();
      expect(keyExprs, contains('zenoh/dart/test/wild/a'));
      expect(keyExprs, contains('zenoh/dart/test/wild/b'));
    });

    test('stream does not emit for non-matching key expressions', () async {
      final subscriber =
          session2.declareSubscriber('zenoh/dart/test/specific');
      addTearDown(subscriber.close);

      await Future<void>.delayed(const Duration(seconds: 1));

      session1.put('zenoh/dart/test/other', 'unrelated');

      // Wait a bit and verify no samples arrive
      await expectLater(
        subscriber.stream.first.timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
