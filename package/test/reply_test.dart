import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('Reply', () {
    late Sample testSample;

    setUp(() {
      testSample = Sample(
        keyExpr: 'demo/test',
        payload: 'hello',
        payloadBytes: Uint8List.fromList([104, 101, 108, 108, 111]),
        kind: SampleKind.put,
        encoding: 'text/plain',
      );
    });

    test('isOk returns true for ok reply', () {
      final reply = Reply.ok(testSample);
      expect(reply.isOk, isTrue);
    });

    test('ok returns sample for ok reply', () {
      final reply = Reply.ok(testSample);
      final sample = reply.ok;
      expect(sample.keyExpr, equals('demo/test'));
      expect(sample.payload, equals('hello'));
      expect(sample.kind, equals(SampleKind.put));
      expect(sample.encoding, equals('text/plain'));
    });

    test('error throws StateError on ok reply', () {
      final reply = Reply.ok(testSample);
      expect(() => reply.error, throwsStateError);
    });

    test('isOk returns false for error reply', () {
      final replyError = ReplyError(
        payloadBytes: Uint8List.fromList([101, 114, 114]),
        payload: 'err',
        encoding: 'text/plain',
      );
      final reply = Reply.error(replyError);
      expect(reply.isOk, isFalse);
    });

    test('error returns ReplyError for error reply', () {
      final replyError = ReplyError(
        payloadBytes: Uint8List.fromList([101, 114, 114]),
        payload: 'err',
        encoding: 'text/plain',
      );
      final reply = Reply.error(replyError);
      final err = reply.error;
      expect(err.payload, equals('err'));
      expect(err.payloadBytes, equals(Uint8List.fromList([101, 114, 114])));
      expect(err.encoding, equals('text/plain'));
    });

    test('ok throws StateError on error reply', () {
      final replyError = ReplyError(
        payloadBytes: Uint8List.fromList([101]),
        payload: 'e',
      );
      final reply = Reply.error(replyError);
      expect(() => reply.ok, throwsStateError);
    });
  });

  group('ReplyError', () {
    test('construction roundtrips all fields', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final err = ReplyError(
        payloadBytes: bytes,
        payload: 'test error',
        encoding: 'application/json',
      );
      expect(err.payloadBytes, equals(bytes));
      expect(err.payload, equals('test error'));
      expect(err.encoding, equals('application/json'));
    });

    test('with null encoding', () {
      final err = ReplyError(
        payloadBytes: Uint8List.fromList([1]),
        payload: 'x',
      );
      expect(err.encoding, isNull);
    });

    test('with empty payload', () {
      final err = ReplyError(
        payloadBytes: Uint8List(0),
        payload: '',
        encoding: 'text/plain',
      );
      expect(err.payloadBytes, isEmpty);
      expect(err.payload, isEmpty);
    });
  });
}
