// SHM Get/Queryable + ZBytes.isShmBacked tests
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

/// Helper to allocate an SHM buffer, write a string into it, and convert
/// to ZBytes.  Allocates exactly [message.length] bytes for zero-copy
/// round-trip fidelity.
ZBytes _shmStringToZBytes(ShmProvider provider, String message) {
  final encoded = utf8.encode(message);
  final buffer = provider.alloc(encoded.length)!;
  final dataPtr = buffer.data;
  for (var i = 0; i < encoded.length; i++) {
    dataPtr[i] = encoded[i];
  }
  return buffer.toBytes();
}

void main() {
  group('SHM Get/Queryable (TCP 17473)', () {
    late Session sessionA;
    late Session sessionB;
    late ShmProvider provider;

    setUp(() async {
      sessionA = Session.open(
        config: Config()
          ..insertJson5('listen/endpoints', '["tcp/127.0.0.1:17473"]'),
      );
      await Future.delayed(Duration(milliseconds: 500));
      sessionB = Session.open(
        config: Config()
          ..insertJson5('connect/endpoints', '["tcp/127.0.0.1:17473"]'),
      );
      await Future.delayed(Duration(milliseconds: 500));
      provider = ShmProvider(size: 65536);
    });

    tearDown(() async {
      provider.close();
      sessionB.close();
      sessionA.close();
    });

    test('SHM payload delivered to queryable via get', () async {
      final receivedPayload = Completer<Uint8List>();
      final queryable = sessionA.declareQueryable(
        'zenoh/dart/test/shm-q/payload',
      );
      addTearDown(queryable.close);

      queryable.stream.listen((query) {
        if (query.payloadBytes != null) {
          receivedPayload.complete(query.payloadBytes!);
        } else {
          receivedPayload.completeError('No payload received');
        }
        query.reply('zenoh/dart/test/shm-q/payload', 'ok');
        query.dispose();
      });

      await Future.delayed(Duration(milliseconds: 200));

      final shmBytes = _shmStringToZBytes(provider, 'shm query data');

      await sessionB
          .get('zenoh/dart/test/shm-q/payload', payload: shmBytes)
          .toList();

      final payload = await receivedPayload.future.timeout(
        Duration(seconds: 5),
      );
      expect(utf8.decode(payload), equals('shm query data'));
    });

    test(
      'non-SHM ZBytes.fromUint8List payload delivered to queryable via get',
      () async {
        final receivedPayload = Completer<Uint8List>();
        final queryable = sessionA.declareQueryable(
          'zenoh/dart/test/shm-q/frombytes',
        );
        addTearDown(queryable.close);

        queryable.stream.listen((query) {
          if (query.payloadBytes != null) {
            receivedPayload.complete(query.payloadBytes!);
          } else {
            receivedPayload.completeError('No payload received');
          }
          query.reply('zenoh/dart/test/shm-q/frombytes', 'ok');
          query.dispose();
        });

        await Future.delayed(Duration(milliseconds: 200));

        final zbytes = ZBytes.fromUint8List(
          Uint8List.fromList(utf8.encode('from bytes')),
        );
        addTearDown(zbytes.dispose);

        await sessionB
            .get('zenoh/dart/test/shm-q/frombytes', payload: zbytes)
            .toList();

        final payload = await receivedPayload.future.timeout(
          Duration(seconds: 5),
        );
        expect(utf8.decode(payload), equals('from bytes'));
      },
    );

    test('SHM queryable reply received by get caller', () async {
      final queryable = sessionA.declareQueryable(
        'zenoh/dart/test/shm-q/reply',
      );
      addTearDown(queryable.close);

      queryable.stream.listen((query) {
        final shmReply = _shmStringToZBytes(provider, 'shm reply data');
        query.replyBytes('zenoh/dart/test/shm-q/reply', shmReply);
        query.dispose();
      });

      await Future.delayed(Duration(milliseconds: 200));

      final replies = await sessionB
          .get('zenoh/dart/test/shm-q/reply')
          .toList();

      expect(replies, hasLength(1));
      expect(replies.first.isOk, isTrue);
      expect(
        utf8.decode(replies.first.ok.payloadBytes),
        equals('shm reply data'),
      );
    });

    test('SHM get payload + SHM reply payload end-to-end', () async {
      final providerB = ShmProvider(size: 65536);
      addTearDown(providerB.close);

      final receivedPayload = Completer<Uint8List>();
      final queryable = sessionA.declareQueryable(
        'zenoh/dart/test/shm-q/bidir',
      );
      addTearDown(queryable.close);

      queryable.stream.listen((query) {
        if (query.payloadBytes != null) {
          receivedPayload.complete(query.payloadBytes!);
        } else {
          receivedPayload.completeError('No payload received');
        }
        // Reply with SHM payload from provider (sessionA side)
        final shmReply = _shmStringToZBytes(provider, 'shm answer');
        query.replyBytes('zenoh/dart/test/shm-q/bidir', shmReply);
        query.dispose();
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Send get with SHM payload from providerB (sessionB side)
      final shmQuery = _shmStringToZBytes(providerB, 'shm query');

      final replies = await sessionB
          .get('zenoh/dart/test/shm-q/bidir', payload: shmQuery)
          .toList();

      // Verify queryable received the SHM query payload
      final queryPayload = await receivedPayload.future.timeout(
        Duration(seconds: 5),
      );
      expect(utf8.decode(queryPayload), equals('shm query'));

      // Verify get caller received the SHM reply
      expect(replies, hasLength(1));
      expect(replies.first.isOk, isTrue);
      expect(utf8.decode(replies.first.ok.payloadBytes), equals('shm answer'));
    });

    test('SHM queryable receives non-SHM query transparently', () async {
      final receivedPayload = Completer<Uint8List>();
      final queryable = sessionA.declareQueryable(
        'zenoh/dart/test/shm-q/mixed-nonshm-q',
      );
      addTearDown(queryable.close);

      queryable.stream.listen((query) {
        if (query.payloadBytes != null) {
          receivedPayload.complete(query.payloadBytes!);
        } else {
          receivedPayload.completeError('No payload received');
        }
        // Reply with SHM payload
        final shmReply = _shmStringToZBytes(provider, 'shm mixed reply');
        query.replyBytes('zenoh/dart/test/shm-q/mixed-nonshm-q', shmReply);
        query.dispose();
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Send non-SHM payload
      final zbytes = ZBytes.fromUint8List(
        Uint8List.fromList(utf8.encode('regular query')),
      );
      addTearDown(zbytes.dispose);

      final replies = await sessionB
          .get('zenoh/dart/test/shm-q/mixed-nonshm-q', payload: zbytes)
          .toList();

      // Verify queryable received non-SHM payload
      final queryPayload = await receivedPayload.future.timeout(
        Duration(seconds: 5),
      );
      expect(utf8.decode(queryPayload), equals('regular query'));

      // Verify get caller received SHM reply
      expect(replies, hasLength(1));
      expect(replies.first.isOk, isTrue);
      expect(
        utf8.decode(replies.first.ok.payloadBytes),
        equals('shm mixed reply'),
      );
    });

    test('non-SHM queryable receives SHM query transparently', () async {
      final receivedPayload = Completer<Uint8List>();
      final queryable = sessionA.declareQueryable(
        'zenoh/dart/test/shm-q/mixed-shm-q',
      );
      addTearDown(queryable.close);

      queryable.stream.listen((query) {
        if (query.payloadBytes != null) {
          receivedPayload.complete(query.payloadBytes!);
        } else {
          receivedPayload.completeError('No payload received');
        }
        // Reply with regular string (non-SHM)
        query.reply('zenoh/dart/test/shm-q/mixed-shm-q', 'regular reply');
        query.dispose();
      });

      await Future.delayed(Duration(milliseconds: 200));

      // Send SHM payload
      final shmQuery = _shmStringToZBytes(provider, 'shm to regular');

      final replies = await sessionB
          .get('zenoh/dart/test/shm-q/mixed-shm-q', payload: shmQuery)
          .toList();

      // Verify queryable received SHM payload transparently
      final queryPayload = await receivedPayload.future.timeout(
        Duration(seconds: 5),
      );
      expect(utf8.decode(queryPayload), equals('shm to regular'));

      // Verify get caller received non-SHM reply
      expect(replies, hasLength(1));
      expect(replies.first.isOk, isTrue);
      expect(
        utf8.decode(replies.first.ok.payloadBytes),
        equals('regular reply'),
      );
    });
  });

  group('ZBytes.isShmBacked', () {
    late ShmProvider provider;

    setUp(() {
      provider = ShmProvider(size: 65536);
    });

    tearDown(() {
      provider.close();
    });

    test('returns true for SHM-backed ZBytes', () {
      final zbytes = _shmStringToZBytes(provider, 'shm data');
      addTearDown(zbytes.dispose);
      expect(zbytes.isShmBacked, isTrue);
    });

    test('returns false for ZBytes.fromUint8List', () {
      final zbytes = ZBytes.fromUint8List(Uint8List.fromList([1, 2, 3]));
      addTearDown(zbytes.dispose);
      expect(zbytes.isShmBacked, isFalse);
    });

    test('returns false for ZBytes.fromString', () {
      final zbytes = ZBytes.fromString('hello');
      addTearDown(zbytes.dispose);
      expect(zbytes.isShmBacked, isFalse);
    });

    test('throws StateError on consumed ZBytes', () {
      final zbytes = ZBytes.fromString('consumed');
      zbytes.markConsumed();
      expect(() => zbytes.isShmBacked, throwsStateError);
    });

    test('throws StateError on disposed ZBytes', () {
      final zbytes = ZBytes.fromString('disposed');
      zbytes.dispose();
      expect(() => zbytes.isShmBacked, throwsStateError);
    });
  });
}
