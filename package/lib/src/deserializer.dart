import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' show ze_deserializer_t;
import 'bytes.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A zenoh deserializer for reading structured payloads.
///
/// Wraps `ze_deserializer_t`. Created from a [ZBytes] instance.
/// Call [dispose] when finished to free native resources.
class ZDeserializer {
  final Pointer<ze_deserializer_t> _ptr;
  bool _disposed = false;

  /// Creates a deserializer from the given [bytes].
  ///
  /// The [bytes] must remain valid for the lifetime of this deserializer.
  ZDeserializer(ZBytes bytes) : _ptr = _create(bytes);

  static Pointer<ze_deserializer_t> _create(ZBytes bytes) {
    final size = bindings.zd_deserializer_sizeof();
    final Pointer<ze_deserializer_t> ptr = calloc.allocate<ze_deserializer_t>(
      size,
    );
    final loaned = bindings.zd_bytes_loan(bytes.nativePtr.cast());
    bindings.zd_deserializer_from_bytes(loaned, ptr);
    return ptr;
  }

  void _checkState() {
    if (_disposed) throw StateError('ZDeserializer has been disposed');
  }

  /// Returns true if all data has been deserialized.
  bool get isDone {
    _checkState();
    return bindings.zd_deserializer_is_done(_ptr);
  }

  /// Deserializes a uint8 value.
  int deserializeUint8() {
    _checkState();
    final out = calloc<Uint8>();
    try {
      final rc = bindings.zd_deserializer_deserialize_uint8(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize uint8', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a uint16 value.
  int deserializeUint16() {
    _checkState();
    final out = calloc<Uint16>();
    try {
      final rc = bindings.zd_deserializer_deserialize_uint16(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize uint16', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a uint32 value.
  int deserializeUint32() {
    _checkState();
    final out = calloc<Uint32>();
    try {
      final rc = bindings.zd_deserializer_deserialize_uint32(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize uint32', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a uint64 value.
  int deserializeUint64() {
    _checkState();
    final out = calloc<Uint64>();
    try {
      final rc = bindings.zd_deserializer_deserialize_uint64(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize uint64', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes an int8 value.
  int deserializeInt8() {
    _checkState();
    final out = calloc<Int8>();
    try {
      final rc = bindings.zd_deserializer_deserialize_int8(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize int8', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes an int16 value.
  int deserializeInt16() {
    _checkState();
    final out = calloc<Int16>();
    try {
      final rc = bindings.zd_deserializer_deserialize_int16(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize int16', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes an int32 value.
  int deserializeInt32() {
    _checkState();
    final out = calloc<Int32>();
    try {
      final rc = bindings.zd_deserializer_deserialize_int32(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize int32', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes an int64 value.
  int deserializeInt64() {
    _checkState();
    final out = calloc<Int64>();
    try {
      final rc = bindings.zd_deserializer_deserialize_int64(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize int64', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a float value.
  double deserializeFloat() {
    _checkState();
    final out = calloc<Float>();
    try {
      final rc = bindings.zd_deserializer_deserialize_float(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize float', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a double value.
  double deserializeDouble() {
    _checkState();
    final out = calloc<Double>();
    try {
      final rc = bindings.zd_deserializer_deserialize_double(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize double', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a bool value.
  bool deserializeBool() {
    _checkState();
    final out = calloc<Bool>();
    try {
      final rc = bindings.zd_deserializer_deserialize_bool(_ptr, out);
      if (rc != 0) throw ZenohException('Failed to deserialize bool', rc);
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Deserializes a UTF-8 string value.
  String deserializeString() {
    _checkState();
    final Pointer<Void> ownedStr = calloc.allocate(bindings.zd_string_sizeof());
    try {
      final rc = bindings.zd_deserializer_deserialize_string(
        _ptr,
        ownedStr.cast(),
      );
      if (rc != 0) throw ZenohException('Failed to deserialize string', rc);
      final loanedStr = bindings.zd_string_loan(ownedStr.cast());
      final data = bindings.zd_string_data(loanedStr);
      final len = bindings.zd_string_len(loanedStr);
      final result = data.cast<Utf8>().toDartString(length: len);
      return result;
    } finally {
      bindings.zd_string_drop(ownedStr.cast());
      calloc.free(ownedStr);
    }
  }

  /// Deserializes a byte buffer.
  Uint8List deserializeBytes() {
    _checkState();
    final Pointer<Void> ownedBytes = calloc.allocate(
      bindings.zd_bytes_sizeof(),
    );
    try {
      final rc = bindings.zd_deserializer_deserialize_buf(
        _ptr,
        ownedBytes.cast(),
      );
      if (rc != 0) throw ZenohException('Failed to deserialize bytes', rc);
      final len = bindings.zd_bytes_len(ownedBytes.cast());
      if (len == 0) return Uint8List(0);
      final buf = malloc<Uint8>(len);
      try {
        bindings.zd_bytes_to_buf(ownedBytes.cast(), buf, len);
        return Uint8List.fromList(buf.asTypedList(len));
      } finally {
        malloc.free(buf);
      }
    } finally {
      bindings.zd_bytes_drop(ownedBytes.cast());
      calloc.free(ownedBytes);
    }
  }

  /// Deserializes a sequence length header.
  int deserializeSequenceLength() {
    _checkState();
    final out = calloc<Size>();
    try {
      final rc = bindings.zd_deserializer_deserialize_sequence_length(
        _ptr,
        out,
      );
      if (rc != 0) {
        throw ZenohException('Failed to deserialize sequence length', rc);
      }
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Releases native resources held by this deserializer.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_ptr);
  }
}
