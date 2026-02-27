import 'package:test/test.dart';
import 'package:zenoh/src/exceptions.dart';
import 'package:zenoh/src/keyexpr.dart';

void main() {
  group('KeyExpr round-trip', () {
    test('simple expression', () {
      final ke = KeyExpr('demo/test');
      expect(ke.value, equals('demo/test'));
      ke.dispose();
    });

    test('hierarchical expression', () {
      final ke = KeyExpr('demo/example/zenoh-dart/test');
      expect(ke.value, equals('demo/example/zenoh-dart/test'));
      ke.dispose();
    });

    test('single wildcard', () {
      final ke = KeyExpr('demo/*');
      expect(ke.value, equals('demo/*'));
      ke.dispose();
    });

    test('double wildcard', () {
      final ke = KeyExpr('demo/**');
      expect(ke.value, equals('demo/**'));
      ke.dispose();
    });

    test('single segment (no slash)', () {
      final ke = KeyExpr('test');
      expect(ke.value, equals('test'));
      ke.dispose();
    });

    test('empty string throws ZenohException', () {
      expect(() => KeyExpr(''), throwsA(isA<ZenohException>()));
    });

    test('dispose releases resources', () {
      final ke = KeyExpr('demo/test');
      expect(() => ke.dispose(), returnsNormally);
    });

    test('dispose is idempotent', () {
      final ke = KeyExpr('demo/test');
      ke.dispose();
      expect(() => ke.dispose(), returnsNormally);
    });
  });
}
