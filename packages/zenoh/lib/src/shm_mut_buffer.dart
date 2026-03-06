import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A mutable shared memory buffer allocated from an [ShmProvider].
///
/// Wraps `z_owned_shm_mut_t`. Call [dispose] when done to release
/// native resources, unless the buffer has been consumed by [toBytes].
class ShmMutBuffer {
  final Pointer<Void> _ptr;
  bool _disposed = false;
  bool _consumed = false;

  /// Creates an ShmMutBuffer wrapping a native pointer.
  ///
  /// This is called internally by [ShmProvider.alloc].
  ShmMutBuffer.fromNative(this._ptr);

  void _ensureUsable() {
    if (_disposed) throw StateError('ShmMutBuffer has been disposed');
    if (_consumed) throw StateError('ShmMutBuffer has been consumed');
  }

  /// Returns the length (in bytes) of this buffer.
  int get length {
    _ensureUsable();
    final loaned = bindings.zd_shm_mut_loan_mut(_ptr.cast());
    return bindings.zd_shm_mut_len(loaned);
  }

  /// Returns a mutable pointer to the buffer data.
  ///
  /// Use this to write data into the SHM buffer before calling [toBytes].
  Pointer<Uint8> get data {
    _ensureUsable();
    final loaned = bindings.zd_shm_mut_loan_mut(_ptr.cast());
    return bindings.zd_shm_mut_data_mut(loaned);
  }

  /// Converts this SHM buffer into a [ZBytes] (zero-copy).
  ///
  /// This consumes the buffer -- subsequent operations will throw
  /// [StateError]. The caller owns the returned [ZBytes] and must
  /// call [ZBytes.dispose] when done.
  ///
  /// Throws [ZenohException] if the conversion fails.
  ZBytes toBytes() {
    _ensureUsable();
    final Pointer<Void> bytesPtr = calloc.allocate(bindings.zd_bytes_sizeof());
    final rc = bindings.zd_bytes_from_shm_mut(bytesPtr.cast(), _ptr.cast());
    if (rc != 0) {
      calloc.free(bytesPtr);
      throw ZenohException('Failed to convert ShmMutBuffer to ZBytes', rc);
    }
    _consumed = true;
    return ZBytes.fromNative(bytesPtr);
  }

  /// Releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  /// If the buffer was consumed by [toBytes], only frees the calloc'd
  /// wrapper memory (the native SHM data is owned by the ZBytes).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_consumed) {
      bindings.zd_shm_mut_drop(_ptr.cast());
    }
    calloc.free(_ptr);
  }
}
