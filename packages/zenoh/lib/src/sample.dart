/// The kind of a sample (put or delete).
enum SampleKind {
  /// A put sample: data was published.
  put,

  /// A delete sample: data was deleted.
  delete,
}

/// A sample received from a subscriber.
///
/// Contains the key expression, payload, kind, and optional attachment
/// extracted from a zenoh sample notification.
class Sample {
  /// The key expression the sample was published on.
  final String keyExpr;

  /// The payload as a UTF-8 string.
  final String payload;

  /// The kind of sample (put or delete).
  final SampleKind kind;

  /// Optional attachment metadata as a UTF-8 string.
  final String? attachment;

  /// The encoding of the payload as a MIME type string, or null if unknown.
  final String? encoding;

  /// Creates a [Sample] with the given fields.
  const Sample({
    required this.keyExpr,
    required this.payload,
    required this.kind,
    this.attachment,
    this.encoding,
  });
}
