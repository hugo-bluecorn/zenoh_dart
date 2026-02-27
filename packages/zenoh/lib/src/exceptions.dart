/// Exception thrown when a zenoh operation fails.
///
/// Carries a human-readable [message] and the native [returnCode]
/// from the zenoh-c API.
class ZenohException implements Exception {
  /// Human-readable description of the error.
  final String message;

  /// Return code from the zenoh-c API (0 = success, negative = error).
  final int returnCode;

  /// Creates a [ZenohException] with the given [message] and [returnCode].
  ZenohException(this.message, this.returnCode);

  @override
  String toString() => 'ZenohException: $message (code: $returnCode)';
}
