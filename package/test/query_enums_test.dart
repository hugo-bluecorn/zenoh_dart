import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('QueryTarget', () {
    test('has correct values', () {
      expect(QueryTarget.bestMatching.index, 0);
      expect(QueryTarget.all.index, 1);
      expect(QueryTarget.allComplete.index, 2);
      expect(QueryTarget.values.length, 3);
    });

    test('values are distinct', () {
      final indices = QueryTarget.values.map((v) => v.index).toSet();
      expect(indices.length, QueryTarget.values.length);
    });
  });

  group('ConsolidationMode', () {
    test('has correct values via value getter', () {
      expect(ConsolidationMode.auto.value, -1);
      expect(ConsolidationMode.none.value, 0);
      expect(ConsolidationMode.monotonic.value, 1);
      expect(ConsolidationMode.latest.value, 2);
    });

    test('auto maps to -1', () {
      expect(ConsolidationMode.auto.value, equals(-1));
    });
  });
}
