import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_lib.dart';

/// A Zenoh byte payload.
///
/// Wraps `z_owned_bytes_t`. Use [ZBytes.fromString] or [ZBytes.fromUint8List]
/// to create a payload, and [toStr] to extract its content as a string.
///
/// Must be [dispose]d when no longer needed to release native memory.
class ZBytes {
  final Pointer<Void> _ptr;
  bool _disposed = false;
  bool _consumed = false;

  ZBytes._(this._ptr);

  /// Creates [ZBytes] wrapping an existing native z_owned_bytes_t pointer.
  ///
  /// Used internally by [ShmMutBuffer.toBytes] for zero-copy conversion.
  ZBytes.fromNative(this._ptr);

  /// Creates [ZBytes] by copying the given [value] string.
  ///
  /// Throws [ZenohException] if the native copy fails.
  factory ZBytes.fromString(String value) {
    final Pointer<Void> ptr = calloc.allocate(bindings.zd_bytes_sizeof());
    final nativeStr = value.toNativeUtf8();
    try {
      final rc = bindings.zd_bytes_copy_from_str(ptr.cast(), nativeStr.cast());
      if (rc != 0) {
        calloc.free(ptr);
        throw ZenohException('Failed to create ZBytes from string', rc);
      }
    } finally {
      malloc.free(nativeStr);
    }
    return ZBytes._(ptr);
  }

  /// Creates [ZBytes] by copying the given [data] buffer.
  ///
  /// Throws [ZenohException] if the native copy fails.
  factory ZBytes.fromUint8List(Uint8List data) {
    final Pointer<Void> ptr = calloc.allocate(bindings.zd_bytes_sizeof());
    final Pointer<Uint8> nativeBuf = calloc<Uint8>(data.length);
    for (var i = 0; i < data.length; i++) {
      nativeBuf[i] = data[i];
    }
    try {
      final rc = bindings.zd_bytes_copy_from_buf(
        ptr.cast(),
        nativeBuf,
        data.length,
      );
      if (rc != 0) {
        calloc.free(ptr);
        throw ZenohException('Failed to create ZBytes from buffer', rc);
      }
    } finally {
      calloc.free(nativeBuf);
    }
    return ZBytes._(ptr);
  }

  /// Converts the payload to a Dart string.
  ///
  /// Throws [StateError] if this [ZBytes] has been disposed.
  /// Throws [ZenohException] if the conversion fails.
  /// Internal: returns the native pointer for use by Session.put/putBytes.
  Pointer<Void> get nativePtr {
    _ensureNotDisposed();
    _ensureNotConsumed();
    return _ptr;
  }

  /// Internal: called by Session after consuming the bytes via z_bytes_move.
  void markConsumed() {
    _consumed = true;
  }

  String toStr() {
    _ensureNotDisposed();
    _ensureNotConsumed();
    final loaned = bindings.zd_bytes_loan(_ptr.cast());
    final Pointer<Void> ownedStr = calloc.allocate(bindings.zd_string_sizeof());
    final rc = bindings.zd_bytes_to_string(loaned, ownedStr.cast());
    if (rc != 0) {
      calloc.free(ownedStr);
      throw ZenohException('Failed to convert ZBytes to string', rc);
    }
    final loanedStr = bindings.zd_string_loan(ownedStr.cast());
    final data = bindings.zd_string_data(loanedStr);
    final len = bindings.zd_string_len(loanedStr);
    final result = data.cast<Utf8>().toDartString(length: len);
    bindings.zd_string_drop(ownedStr.cast());
    calloc.free(ownedStr);
    return result;
  }

  /// Reads the payload content as a [Uint8List].
  ///
  /// This is a non-destructive read -- the [ZBytes] can still be used after
  /// calling this method.
  ///
  /// Throws [StateError] if this [ZBytes] has been disposed or consumed.
  Uint8List toBytes() {
    _ensureNotDisposed();
    _ensureNotConsumed();
    final len = bindings.zd_bytes_len(_ptr.cast());
    if (len == 0) return Uint8List(0);
    final buf = malloc<Uint8>(len);
    try {
      bindings.zd_bytes_to_buf(_ptr.cast(), buf, len);
      return Uint8List.fromList(buf.asTypedList(len));
    } finally {
      malloc.free(buf);
    }
  }

  /// Creates an independent shallow copy of this [ZBytes].
  ///
  /// The clone shares the underlying reference-counted data but has its own
  /// native ownership -- disposing the clone does not affect the original,
  /// and vice versa.
  ///
  /// Throws [StateError] if this [ZBytes] has been disposed or consumed.
  /// Throws [ZenohException] if the native clone fails.
  ZBytes clone() {
    _ensureNotDisposed();
    _ensureNotConsumed();
    final Pointer<Void> dst = calloc.allocate(bindings.zd_bytes_sizeof());
    final rc = bindings.zd_bytes_clone(dst.cast(), _ptr.cast());
    if (rc != 0) {
      calloc.free(dst);
      throw ZenohException('Failed to clone ZBytes', rc);
    }
    return ZBytes._(dst);
  }

  /// Returns whether this payload is backed by shared memory.
  ///
  /// Throws [StateError] if this [ZBytes] has been consumed or disposed.
  bool get isShmBacked {
    _ensureNotDisposed();
    _ensureNotConsumed();
    return bindings.zd_bytes_is_shm(_ptr.cast()) == 1;
  }

  /// Releases native resources held by this payload.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    if (_consumed) return;
    _disposed = true;
    bindings.zd_bytes_drop(_ptr.cast());
    calloc.free(_ptr);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('ZBytes has been disposed');
  }

  void _ensureNotConsumed() {
    if (_consumed) throw StateError('ZBytes has been consumed');
  }
}
