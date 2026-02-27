import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ZBytes round-trip', () {
    test('from string round-trip', () {
      // Given: a string "hello"
      // When: ZBytes.fromString("hello") is created and .toStr() is called
      final zbytes = ZBytes.fromString('hello');
      final result = zbytes.toStr();

      // Then: the returned string equals "hello"
      expect(result, equals('hello'));
      zbytes.dispose();
    });

    test('from Uint8List round-trip', () {
      // Given: a Uint8List containing [104, 101, 108, 108, 111] (ASCII "hello")
      final data = Uint8List.fromList([104, 101, 108, 108, 111]);

      // When: ZBytes.fromUint8List(bytes) is created and .toStr() is called
      final zbytes = ZBytes.fromUint8List(data);
      final result = zbytes.toStr();

      // Then: the returned string equals "hello"
      expect(result, equals('hello'));
      zbytes.dispose();
    });

    test('dispose releases resources', () {
      // Given: a ZBytes object
      final zbytes = ZBytes.fromString('test');

      // When: zbytes.dispose() is called
      // Then: no exception is thrown
      expect(() => zbytes.dispose(), returnsNormally);
    });

    test('dispose is idempotent (double-drop safe)', () {
      // Given: a ZBytes that has been disposed
      final zbytes = ZBytes.fromString('test');
      zbytes.dispose();

      // When: zbytes.dispose() is called again
      // Then: no exception is thrown
      expect(() => zbytes.dispose(), returnsNormally);
    });

    test('from string with unicode content', () {
      // Given: a string "hello world"
      // When: ZBytes.fromString("hello world") is created and .toStr() is called
      final zbytes = ZBytes.fromString('hello world');
      final result = zbytes.toStr();

      // Then: the returned string equals "hello world"
      expect(result, equals('hello world'));
      zbytes.dispose();
    });

    test('from empty string', () {
      // Given: an empty string ""
      // When: ZBytes.fromString("") is created and .toStr() is called
      final zbytes = ZBytes.fromString('');
      final result = zbytes.toStr();

      // Then: the returned string equals ""
      expect(result, equals(''));
      zbytes.dispose();
    });

    test('from empty Uint8List', () {
      // Given: an empty Uint8List
      // When: ZBytes.fromUint8List(Uint8List(0)) is created and .toStr() is called
      final zbytes = ZBytes.fromUint8List(Uint8List(0));
      final result = zbytes.toStr();

      // Then: the returned string equals ""
      expect(result, equals(''));
      zbytes.dispose();
    });

    test('from large payload', () {
      // Given: a string of 10,000 "a" characters
      final largeString = 'a' * 10000;

      // When: ZBytes.fromString(largeString) is created and .toStr() is called
      final zbytes = ZBytes.fromString(largeString);
      final result = zbytes.toStr();

      // Then: the returned string equals the original
      expect(result, equals(largeString));
      zbytes.dispose();
    });
  });

  group('Barrel export', () {
    test('provides all public types', () {
      // Given: the zenoh package is imported via package:zenoh/zenoh.dart
      // When: the types Config, Session, KeyExpr, ZBytes, ZenohException
      //       are referenced
      // Then: all types are accessible (test compiles and runs)
      expect(Config, isNotNull);
      expect(Session, isNotNull);
      expect(KeyExpr, isNotNull);
      expect(ZBytes, isNotNull);
      expect(ZenohException, isNotNull);
    });
  });
}
