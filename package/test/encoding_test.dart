import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('Encoding', () {
    test('predefined constants have correct MIME types', () {
      expect(Encoding.zenohBytes.mimeType, equals('zenoh/bytes'));
      expect(Encoding.zenohString.mimeType, equals('zenoh/string'));
      expect(Encoding.textPlain.mimeType, equals('text/plain'));
      expect(Encoding.applicationJson.mimeType, equals('application/json'));
      expect(
        Encoding.applicationOctetStream.mimeType,
        equals('application/octet-stream'),
      );
      expect(
        Encoding.applicationProtobuf.mimeType,
        equals('application/protobuf'),
      );
      expect(Encoding.textHtml.mimeType, equals('text/html'));
      expect(Encoding.textCsv.mimeType, equals('text/csv'));
      expect(Encoding.imagePng.mimeType, equals('image/png'));
      expect(Encoding.imageJpeg.mimeType, equals('image/jpeg'));
    });

    test('custom constructor accepts arbitrary MIME type', () {
      final encoding = Encoding('application/x-custom');
      expect(encoding.mimeType, equals('application/x-custom'));
    });

    test('toString returns the MIME type string', () {
      expect(Encoding.textPlain.toString(), equals('text/plain'));
      expect(
        Encoding('application/x-custom').toString(),
        equals('application/x-custom'),
      );
    });

    test('equality works for same MIME type', () {
      const a = Encoding('text/plain');
      const b = Encoding('text/plain');
      expect(a, equals(b));
    });
  });

  group('CongestionControl', () {
    test('has block and drop values with correct indices', () {
      expect(CongestionControl.block.index, equals(0));
      expect(CongestionControl.drop.index, equals(1));
      expect(CongestionControl.block, isNot(equals(CongestionControl.drop)));
    });
  });

  group('Priority', () {
    test('has all seven levels with correct indices', () {
      expect(Priority.realTime.index, equals(0));
      expect(Priority.interactiveHigh.index, equals(1));
      expect(Priority.interactiveLow.index, equals(2));
      expect(Priority.dataHigh.index, equals(3));
      expect(Priority.data.index, equals(4));
      expect(Priority.dataLow.index, equals(5));
      expect(Priority.background.index, equals(6));
      expect(Priority.values.length, equals(7));
    });
  });
}
