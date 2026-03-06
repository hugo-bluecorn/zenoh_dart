import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ShmProvider', () {
    test('creates with valid total size', () {
      final provider = ShmProvider(size: 4096);
      addTearDown(provider.close);
      expect(provider, isNotNull);
    });

    test('available returns total pool size initially', () {
      final provider = ShmProvider(size: 4096);
      addTearDown(provider.close);
      expect(provider.available, equals(4096));
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
