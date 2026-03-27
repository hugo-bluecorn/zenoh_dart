// Liveliness token, subscriber, and get tests (Phase 11)
import 'dart:async';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('LivelinessToken lifecycle', () {
    late Session session;

    setUpAll(() {
      session = Session.open();
    });

    tearDownAll(() {
      session.close();
    });

    test('declareLivelinessToken returns a LivelinessToken', () {
      final token = session.declareLivelinessToken(
        'demo/example/liveliness-test',
      );
      expect(token, isA<LivelinessToken>());
      token.close();
    });

    test('LivelinessToken.keyExpr returns declared key expression', () {
      final token = session.declareLivelinessToken(
        'demo/example/liveliness-test',
      );
      expect(token.keyExpr, equals('demo/example/liveliness-test'));
      token.close();
    });

    test('LivelinessToken.close completes without error', () {
      final token = session.declareLivelinessToken(
        'demo/example/liveliness-test',
      );
      expect(() => token.close(), returnsNormally);
    });

    test('LivelinessToken.close is idempotent', () {
      final token = session.declareLivelinessToken(
        'demo/example/liveliness-test',
      );
      token.close();
      expect(() => token.close(), returnsNormally);
    });

    test('declareLivelinessToken on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.declareLivelinessToken(
          'demo/example/liveliness-test',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('declareLivelinessToken with invalid key expression throws '
        'ZenohException', () {
      expect(
        () => session.declareLivelinessToken(''),
        throwsA(isA<ZenohException>()),
      );
    });
  });

  group('Liveliness Subscriber (TCP 17500)', () {
    late Session sessionA;
    late Session sessionB;

    setUp(() async {
      sessionA = Session.open(
        config: Config()
          ..insertJson5('listen/endpoints', '["tcp/127.0.0.1:17500"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      sessionB = Session.open(
        config: Config()
          ..insertJson5('connect/endpoints', '["tcp/127.0.0.1:17500"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDown(() {
      sessionB.close();
      sessionA.close();
    });

    test('declareLivelinessSubscriber returns a Subscriber', () {
      final sub = sessionB.declareLivelinessSubscriber(
        'zenoh/liveliness/test/**',
      );
      expect(sub, isA<Subscriber>());
      sub.close();
    });

    test('Subscriber receives PUT when token is declared', () async {
      final sub = sessionB.declareLivelinessSubscriber(
        'zenoh/liveliness/test/*',
      );
      addTearDown(sub.close);
      await Future.delayed(const Duration(milliseconds: 500));

      final token = sessionA.declareLivelinessToken('zenoh/liveliness/test/1');
      addTearDown(token.close);

      final sample = await sub.stream.first.timeout(const Duration(seconds: 5));
      expect(sample.kind, equals(SampleKind.put));
      expect(sample.keyExpr, contains('zenoh/liveliness/test/1'));
    });

    test('Subscriber receives DELETE when token is closed', () async {
      final sub = sessionB.declareLivelinessSubscriber(
        'zenoh/liveliness/test/*',
      );
      addTearDown(sub.close);
      await Future.delayed(const Duration(milliseconds: 500));

      final token = sessionA.declareLivelinessToken('zenoh/liveliness/test/1');

      // Collect PUT + DELETE in a single subscription
      final samplesFuture = sub.stream
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 10));

      // Close the token after a brief delay to trigger DELETE
      await Future.delayed(const Duration(seconds: 1));
      token.close();

      final samples = await samplesFuture;
      expect(samples[0].kind, equals(SampleKind.put));
      expect(samples[1].kind, equals(SampleKind.delete));
      expect(samples[1].keyExpr, contains('zenoh/liveliness/test/1'));
    });

    test(
      'Multiple tokens produce multiple PUT and individual DELETE',
      () async {
        final sub = sessionB.declareLivelinessSubscriber(
          'zenoh/liveliness/test/*',
        );
        addTearDown(sub.close);
        await Future.delayed(const Duration(milliseconds: 500));

        // Collect all 4 samples (2 PUTs + 2 DELETEs) in a single subscription
        final samplesFuture = sub.stream
            .take(4)
            .toList()
            .timeout(const Duration(seconds: 15));

        final token1 = sessionA.declareLivelinessToken(
          'zenoh/liveliness/test/1',
        );
        final token2 = sessionA.declareLivelinessToken(
          'zenoh/liveliness/test/2',
        );

        // Wait for PUTs to be delivered before closing
        await Future.delayed(const Duration(seconds: 2));

        // Close tokens sequentially
        token1.close();
        await Future.delayed(const Duration(milliseconds: 500));
        token2.close();

        final samples = await samplesFuture;
        expect(samples, hasLength(4));

        final puts = samples.where((s) => s.kind == SampleKind.put).toList();
        final deletes = samples
            .where((s) => s.kind == SampleKind.delete)
            .toList();
        expect(puts, hasLength(2));
        expect(deletes, hasLength(2));
      },
    );

    test('declareLivelinessSubscriber on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.declareLivelinessSubscriber(
          'zenoh/liveliness/test/**',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('declareLivelinessSubscriber with invalid key expression throws '
        'ZenohException', () {
      expect(
        () => sessionA.declareLivelinessSubscriber(''),
        throwsA(isA<ZenohException>()),
      );
    });

    test('Liveliness subscriber close is idempotent', () {
      final sub = sessionA.declareLivelinessSubscriber(
        'zenoh/liveliness/test/**',
      );
      sub.close();
      expect(() => sub.close(), returnsNormally);
    });
  });

  group('Liveliness Get (TCP 17502)', () {
    late Session sessionA;
    late Session sessionB;

    setUp(() async {
      sessionA = Session.open(
        config: Config()
          ..insertJson5('listen/endpoints', '["tcp/127.0.0.1:17502"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      sessionB = Session.open(
        config: Config()
          ..insertJson5('connect/endpoints', '["tcp/127.0.0.1:17502"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDown(() {
      sessionB.close();
      sessionA.close();
    });

    test('livelinessGet returns alive token', () async {
      final token = sessionA.declareLivelinessToken(
        'zenoh/liveliness/test/get1',
      );
      addTearDown(token.close);

      await Future.delayed(const Duration(seconds: 1));

      final replies = await sessionB
          .livelinessGet('zenoh/liveliness/test/*')
          .toList()
          .timeout(const Duration(seconds: 10));

      expect(replies, hasLength(1));
      expect(replies[0].isOk, isTrue);
      expect(replies[0].ok.keyExpr, contains('zenoh/liveliness/test/get1'));
    });

    test('livelinessGet returns empty stream when no tokens alive', () async {
      final replies = await sessionB
          .livelinessGet(
            'zenoh/liveliness/test/*',
            timeout: const Duration(seconds: 2),
          )
          .toList()
          .timeout(const Duration(seconds: 10));

      expect(replies, isEmpty);
    });

    test('livelinessGet returns empty after token dropped', () async {
      final token = sessionA.declareLivelinessToken(
        'zenoh/liveliness/test/get3',
      );
      await Future.delayed(const Duration(seconds: 1));
      token.close();
      await Future.delayed(const Duration(seconds: 1));

      final replies = await sessionB
          .livelinessGet(
            'zenoh/liveliness/test/*',
            timeout: const Duration(seconds: 2),
          )
          .toList()
          .timeout(const Duration(seconds: 10));

      expect(replies, isEmpty);
    });

    test('livelinessGet with custom timeout', () async {
      final token = sessionA.declareLivelinessToken(
        'zenoh/liveliness/test/get4',
      );
      addTearDown(token.close);

      await Future.delayed(const Duration(seconds: 1));

      final replies = await sessionB
          .livelinessGet(
            'zenoh/liveliness/test/*',
            timeout: const Duration(seconds: 5),
          )
          .toList()
          .timeout(const Duration(seconds: 10));

      expect(replies, hasLength(1));
      expect(replies[0].isOk, isTrue);
    });

    test('livelinessGet on closed session throws StateError', () {
      final closedSession = Session.open();
      closedSession.close();
      expect(
        () => closedSession.livelinessGet('zenoh/liveliness/test/*'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    });

    test('livelinessGet with invalid key expression throws ZenohException', () {
      expect(() => sessionA.livelinessGet(''), throwsA(isA<ZenohException>()));
    });
  });

  group('Liveliness Subscriber History (TCP 17501)', () {
    late Session sessionA;
    late Session sessionB;

    setUp(() async {
      sessionA = Session.open(
        config: Config()
          ..insertJson5('listen/endpoints', '["tcp/127.0.0.1:17501"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      sessionB = Session.open(
        config: Config()
          ..insertJson5('connect/endpoints', '["tcp/127.0.0.1:17501"]'),
      );
      await Future.delayed(const Duration(milliseconds: 500));
    });

    tearDown(() {
      sessionB.close();
      sessionA.close();
    });

    test('history=true receives existing alive tokens as PUT', () async {
      // Session A declares a token BEFORE session B subscribes
      final token = sessionA.declareLivelinessToken(
        'zenoh/liveliness/test/hist1',
      );
      addTearDown(token.close);

      // Wait for token to propagate
      await Future.delayed(const Duration(milliseconds: 500));

      // Session B subscribes with history: true — should receive existing token
      final sub = sessionB.declareLivelinessSubscriber(
        'zenoh/liveliness/test/*',
        history: true,
      );
      addTearDown(sub.close);

      final sample = await sub.stream.first.timeout(const Duration(seconds: 5));
      expect(sample.kind, equals(SampleKind.put));
      expect(sample.keyExpr, contains('zenoh/liveliness/test/hist1'));
    });

    test('history=false does NOT receive existing alive tokens', () async {
      // Session A declares a token BEFORE session B subscribes
      final token = sessionA.declareLivelinessToken(
        'zenoh/liveliness/test/hist2',
      );
      addTearDown(token.close);

      // Wait for token to propagate
      await Future.delayed(const Duration(milliseconds: 500));

      // Session B subscribes with history: false (default) — should NOT
      // receive the existing token
      final sub = sessionB.declareLivelinessSubscriber(
        'zenoh/liveliness/test/*',
        history: false,
      );
      addTearDown(sub.close);

      // Wait 2 seconds and verify no sample arrives
      expect(
        () => sub.stream.first.timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
