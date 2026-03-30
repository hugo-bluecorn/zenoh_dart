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

    test('value after dispose throws StateError', () {
      final ke = KeyExpr('demo/test');
      ke.dispose();
      expect(() => ke.value, throwsStateError);
    });
  });

  group('KeyExpr.intersects', () {
    test('exact match intersects', () {
      final a = KeyExpr('demo/example/test');
      final b = KeyExpr('demo/example/test');
      expect(a.intersects(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('double-wildcard intersects specific', () {
      final a = KeyExpr('demo/**');
      final b = KeyExpr('demo/example/test');
      expect(a.intersects(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('single-level wildcard intersects', () {
      final a = KeyExpr('demo/*/test');
      final b = KeyExpr('demo/example/test');
      expect(a.intersects(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('non-matching does not intersect', () {
      final a = KeyExpr('demo/a');
      final b = KeyExpr('demo/b');
      expect(a.intersects(b), isFalse);
      a.dispose();
      b.dispose();
    });

    test('disjoint paths do not intersect', () {
      final a = KeyExpr('demo/example');
      final b = KeyExpr('other/path');
      expect(a.intersects(b), isFalse);
      a.dispose();
      b.dispose();
    });
  });

  group('KeyExpr.includes', () {
    test('wildcard includes specific', () {
      final a = KeyExpr('demo/**');
      final b = KeyExpr('demo/example/test');
      expect(a.includes(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('specific does not include wildcard', () {
      final a = KeyExpr('demo/example/test');
      final b = KeyExpr('demo/**');
      expect(a.includes(b), isFalse);
      a.dispose();
      b.dispose();
    });

    test('exact includes itself', () {
      final a = KeyExpr('demo/example');
      final b = KeyExpr('demo/example');
      expect(a.includes(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('disjoint does not include', () {
      final a = KeyExpr('demo/a');
      final b = KeyExpr('demo/b');
      expect(a.includes(b), isFalse);
      a.dispose();
      b.dispose();
    });
  });

  group('KeyExpr.equals', () {
    test('identical expressions are equal', () {
      final a = KeyExpr('demo/example');
      final b = KeyExpr('demo/example');
      expect(a.equals(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('different expressions are not equal', () {
      final a = KeyExpr('demo/a');
      final b = KeyExpr('demo/b');
      expect(a.equals(b), isFalse);
      a.dispose();
      b.dispose();
    });

    test('wildcard not equal to specific', () {
      final a = KeyExpr('demo/**');
      final b = KeyExpr('demo/example');
      expect(a.equals(b), isFalse);
      a.dispose();
      b.dispose();
    });
  });
}
