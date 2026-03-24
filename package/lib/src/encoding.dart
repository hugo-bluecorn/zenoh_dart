/// Represents the encoding of a zenoh payload.
///
/// Uses MIME type strings to describe the encoding format.
/// Provides predefined constants for common types and supports
/// custom MIME types via the constructor.
class Encoding {
  /// The MIME type string for this encoding.
  final String mimeType;

  /// Creates an [Encoding] with the given [mimeType].
  const Encoding(this.mimeType);

  static const zenohBytes = Encoding('zenoh/bytes');
  static const zenohString = Encoding('zenoh/string');
  static const textPlain = Encoding('text/plain');
  static const applicationJson = Encoding('application/json');
  static const applicationOctetStream = Encoding('application/octet-stream');
  static const applicationProtobuf = Encoding('application/protobuf');
  static const textHtml = Encoding('text/html');
  static const textCsv = Encoding('text/csv');
  static const imagePng = Encoding('image/png');
  static const imageJpeg = Encoding('image/jpeg');

  @override
  String toString() => mimeType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Encoding && mimeType == other.mimeType;

  @override
  int get hashCode => mimeType.hashCode;
}
