import 'dart:typed_data';

/// A 16-byte zenoh entity identifier.
///
/// ZenohId wraps a 16-byte unique identifier assigned to each zenoh session.
/// The hex representation uses LSB-first byte order to match zenoh-c convention.
class ZenohId {
  /// The raw 16-byte identifier.
  final Uint8List bytes;

  /// Creates a ZenohId from a 16-byte [Uint8List].
  ZenohId(Uint8List bytes)
    : bytes = Uint8List.fromList(bytes); // unmodifiable copy

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ZenohId) return false;
    for (var i = 0; i < 16; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final byte in bytes) {
      hash = (hash * 31 + byte) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Returns the hex string representation (LSB-first, matching zenoh-c).
  String toHexString() {
    final sb = StringBuffer();
    for (final byte in bytes) {
      sb.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  @override
  String toString() => toHexString();
}
