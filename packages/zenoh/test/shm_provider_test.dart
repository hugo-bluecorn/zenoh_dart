import 'dart:convert';
import 'dart:ffi';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ShmProvider', () {
    test('creates with valid total size', () {
      final provider = ShmProvider(size: 4096);
      addTearDown(provider.close);
      expect(provider, isNotNull);
    });

    test('available returns a non-negative value', () {
      final provider = ShmProvider(size: 4096);
      addTearDown(provider.close);
      // z_shm_provider_available returns currently free bytes.
      // The default provider may report 0 initially (lazy allocation).
      expect(provider.available, greaterThanOrEqualTo(0));
    });

    test('close completes without error', () {
      final provider = ShmProvider(size: 4096);
      expect(() => provider.close(), returnsNormally);
    });

    test('close is idempotent', () {
      final provider = ShmProvider(size: 4096);
      provider.close();
      expect(() => provider.close(), returnsNormally);
    });

    test('operations after close throw StateError', () {
      final provider = ShmProvider(size: 4096);
      provider.close();

      expect(() => provider.available, throwsStateError);
      expect(
        () => provider.alloc(128),
        throwsStateError,
      );
    });

    test('with zero total size', () {
      // zenoh-c may accept size 0 or reject it
      // If it succeeds, available should be 0
      // If it fails, it should throw ZenohException
      try {
        final provider = ShmProvider(size: 0);
        addTearDown(provider.close);
        expect(provider.available, equals(0));
      } on ZenohException {
        // Also acceptable -- zenoh-c rejected size 0
      }
    });
  });

  group('ShmMutBuffer', () {
    late ShmProvider provider;

    setUp(() {
      provider = ShmProvider(size: 4096);
    });

    tearDown(() {
      provider.close();
    });

    test('alloc returns ShmMutBuffer on success', () {
      final buffer = provider.alloc(128);
      addTearDown(() => buffer?.dispose());
      expect(buffer, isNotNull);
    });

    test('length returns the allocated size', () {
      final buffer = provider.alloc(128)!;
      addTearDown(buffer.dispose);
      expect(buffer.length, equals(128));
    });

    test('allocGcDefragBlocking returns ShmMutBuffer with correct length', () {
      final buffer = provider.allocGcDefragBlocking(256);
      addTearDown(() => buffer?.dispose());
      expect(buffer, isNotNull);
      expect(buffer!.length, equals(256));
    });

    test('dispose frees the buffer without error', () {
      final buffer = provider.alloc(128)!;
      expect(() => buffer.dispose(), returnsNormally);
    });

    test('dispose is idempotent', () {
      final buffer = provider.alloc(128)!;
      buffer.dispose();
      expect(() => buffer.dispose(), returnsNormally);
    });

    test('alloc with size exceeding pool returns null', () {
      // Use the group provider (size 4096) and request more than available
      final buffer = provider.alloc(8192);
      expect(buffer, isNull);
    });

    test('operations after dispose throw StateError', () {
      final buffer = provider.alloc(128)!;
      buffer.dispose();
      expect(() => buffer.length, throwsStateError);
    });

    test('multiple allocations exhaust the pool', () {
      // Allocate buffers until the pool is exhausted
      final buffers = <ShmMutBuffer>[];
      for (var i = 0; i < 10; i++) {
        final buf = provider.alloc(512);
        if (buf == null) break;
        buffers.add(buf);
      }
      addTearDown(() {
        for (final b in buffers) {
          b.dispose();
        }
      });

      // We should have gotten at least one buffer
      expect(buffers, isNotEmpty);
      // And eventually the pool should be exhausted (fewer than 10)
      expect(buffers.length, lessThan(10));
    });

    test('data returns writable pointer', () {
      final buffer = provider.alloc(128)!;
      addTearDown(buffer.dispose);
      final ptr = buffer.data;
      expect(ptr, isNotNull);
    });

    test('data written via pointer survives toBytes round-trip', () {
      final message = 'hello shm';
      final encoded = utf8.encode(message);
      // Allocate exactly the size needed so zero-copy conversion
      // produces a ZBytes with only the written data.
      final buffer = provider.alloc(encoded.length)!;
      final dataPtr = buffer.data;
      for (var i = 0; i < encoded.length; i++) {
        dataPtr[i] = encoded[i];
      }

      final zbytes = buffer.toBytes();
      addTearDown(zbytes.dispose);
      expect(zbytes.toStr(), equals(message));
    });

    test('toBytes consumes the buffer', () {
      final buffer = provider.alloc(128)!;
      final message = 'test';
      final encoded = utf8.encode(message);
      final dataPtr = buffer.data;
      for (var i = 0; i < encoded.length; i++) {
        dataPtr[i] = encoded[i];
      }

      final zbytes = buffer.toBytes();
      addTearDown(zbytes.dispose);
      expect(zbytes, isNotNull);

      // Subsequent operations on buffer should throw StateError
      expect(() => buffer.length, throwsStateError);
      expect(() => buffer.data, throwsStateError);
    });

    test('toBytes after dispose throws StateError', () {
      final buffer = provider.alloc(128)!;
      buffer.dispose();
      expect(() => buffer.toBytes(), throwsStateError);
    });

    test('toBytes called twice throws StateError on second call', () {
      final buffer = provider.alloc(128)!;
      final zbytes = buffer.toBytes();
      addTearDown(zbytes.dispose);

      expect(() => buffer.toBytes(), throwsStateError);
    });

    test('data after toBytes throws StateError', () {
      final buffer = provider.alloc(128)!;
      final zbytes = buffer.toBytes();
      addTearDown(zbytes.dispose);

      expect(() => buffer.data, throwsStateError);
    });
  });
}
