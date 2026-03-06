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
}
