import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A zenoh serializer for building structured payloads.
///
/// Wraps `ze_owned_serializer_t`. Call [finish] to produce a [ZBytes],
/// or [dispose] to release native resources without finishing.
class ZSerializer {
  final Pointer<Void> _ptr;
  bool _finished = false;
  bool _disposed = false;

  /// Creates an empty serializer.
  ZSerializer() : _ptr = _create();

  static Pointer<Void> _create() {
    final size = bindings.zd_serializer_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);
    bindings.zd_serializer_empty(ptr.cast());
    return ptr;
  }

  void _checkState() {
    if (_disposed) throw StateError('ZSerializer has been disposed');
    if (_finished) throw StateError('ZSerializer has been finished');
  }

  Pointer<Void> _loanMut() {
    final out = calloc<Pointer<Void>>();
    bindings.zd_serializer_loan_mut(_ptr.cast(), out.cast());
    final loaned = out.value;
    calloc.free(out);
    return loaned;
  }

  /// Serializes a uint8 value.
  void serializeUint8(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_uint8(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize uint8', rc);
  }

  /// Serializes a uint16 value.
  void serializeUint16(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_uint16(
      _loanMut().cast(),
      value,
    );
    if (rc != 0) throw ZenohException('Failed to serialize uint16', rc);
  }

  /// Serializes a uint32 value.
  void serializeUint32(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_uint32(
      _loanMut().cast(),
      value,
    );
    if (rc != 0) throw ZenohException('Failed to serialize uint32', rc);
  }

  /// Serializes a uint64 value.
  void serializeUint64(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_uint64(
      _loanMut().cast(),
      value,
    );
    if (rc != 0) throw ZenohException('Failed to serialize uint64', rc);
  }

  /// Serializes an int8 value.
  void serializeInt8(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_int8(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize int8', rc);
  }

  /// Serializes an int16 value.
  void serializeInt16(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_int16(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize int16', rc);
  }

  /// Serializes an int32 value.
  void serializeInt32(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_int32(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize int32', rc);
  }

  /// Serializes an int64 value.
  void serializeInt64(int value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_int64(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize int64', rc);
  }

  /// Serializes a float value.
  void serializeFloat(double value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_float(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize float', rc);
  }

  /// Serializes a double value.
  void serializeDouble(double value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_double(
      _loanMut().cast(),
      value,
    );
    if (rc != 0) throw ZenohException('Failed to serialize double', rc);
  }

  /// Serializes a bool value.
  void serializeBool(bool value) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_bool(_loanMut().cast(), value);
    if (rc != 0) throw ZenohException('Failed to serialize bool', rc);
  }

  /// Serializes a UTF-8 string value.
  void serializeString(String value) {
    _checkState();
    final nativeStr = value.toNativeUtf8();
    try {
      final rc = bindings.zd_serializer_serialize_string(
        _loanMut().cast(),
        nativeStr.cast(),
      );
      if (rc != 0) throw ZenohException('Failed to serialize string', rc);
    } finally {
      calloc.free(nativeStr);
    }
  }

  /// Serializes a byte buffer.
  void serializeBytes(Uint8List value) {
    _checkState();
    final Pointer<Uint8> nativeBuf = calloc.allocate(value.length);
    try {
      nativeBuf.asTypedList(value.length).setAll(0, value);
      final rc = bindings.zd_serializer_serialize_buf(
        _loanMut().cast(),
        nativeBuf,
        value.length,
      );
      if (rc != 0) throw ZenohException('Failed to serialize bytes', rc);
    } finally {
      calloc.free(nativeBuf);
    }
  }

  /// Serializes a sequence length header.
  ///
  /// Must be followed by exactly [length] serialized elements of the
  /// same type to form a valid sequence.
  void serializeSequenceLength(int length) {
    _checkState();
    final rc = bindings.zd_serializer_serialize_sequence_length(
      _loanMut().cast(),
      length,
    );
    if (rc != 0) {
      throw ZenohException('Failed to serialize sequence length', rc);
    }
  }

  /// Finishes the serializer and returns the produced [ZBytes].
  ///
  /// The serializer is consumed by this call. After finishing,
  /// no further operations are allowed.
  ///
  /// Throws [StateError] if already finished or disposed.
  ZBytes finish() {
    _checkState();
    _finished = true;
    final Pointer<Void> bytesPtr = calloc.allocate(bindings.zd_bytes_sizeof());
    bindings.zd_serializer_finish(_ptr.cast(), bytesPtr.cast());
    calloc.free(_ptr);
    return ZBytes.fromNative(bytesPtr);
  }

  /// Releases native resources held by this serializer.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  /// Safe to call after [finish] -- no-op since resources were
  /// already transferred.
  void dispose() {
    if (_disposed) return;
    if (_finished) {
      _disposed = true;
      return;
    }
    _disposed = true;
    bindings.zd_serializer_drop(_ptr.cast());
    calloc.free(_ptr);
  }
}
