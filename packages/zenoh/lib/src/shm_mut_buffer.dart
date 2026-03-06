import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_lib.dart';

/// A mutable shared memory buffer allocated from an [ShmProvider].
///
/// Wraps `z_owned_shm_mut_t`. Call [dispose] when done to release
/// native resources, unless the buffer has been consumed by [toBytes].
class ShmMutBuffer {
  final Pointer<Void> _ptr;
  bool _disposed = false;

  /// Creates an ShmMutBuffer wrapping a native pointer.
  ///
  /// This is called internally by [ShmProvider.alloc].
  ShmMutBuffer.fromNative(this._ptr);

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('ShmMutBuffer has been disposed');
  }

  /// Returns the length (in bytes) of this buffer.
  int get length {
    _ensureNotDisposed();
    final loaned = bindings.zd_shm_mut_loan_mut(_ptr.cast());
    return bindings.zd_shm_mut_len(loaned);
  }

  /// Releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.zd_shm_mut_drop(_ptr.cast());
    calloc.free(_ptr);
  }
}
