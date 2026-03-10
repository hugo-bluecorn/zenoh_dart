import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'bindings.dart' as ffi_bindings;
import 'shm_mut_buffer.dart';

/// A shared memory provider for zero-copy data transfer.
///
/// Wraps `z_owned_shm_provider_t`. Call [close] when done to release
/// native resources.
class ShmProvider {
  final Pointer<Void> _ptr;
  bool _closed = false;

  /// Creates an SHM provider with the given total pool [size] in bytes.
  ///
  /// Throws [ZenohException] if the provider cannot be created.
  ShmProvider({required int size}) : _ptr = _create(size);

  static Pointer<Void> _create(int totalSize) {
    final size = ffi_bindings.zd_shm_provider_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);

    final rc = ffi_bindings.zd_shm_provider_new(ptr.cast(), totalSize);
    if (rc != 0) {
      calloc.free(ptr);
      throw ZenohException('Failed to create SHM provider', rc);
    }

    return ptr;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('ShmProvider has been closed');
  }

  /// Returns the available (free) bytes in the SHM pool.
  int get available {
    _ensureOpen();
    final loaned = ffi_bindings.zd_shm_provider_loan(_ptr.cast());
    return ffi_bindings.zd_shm_provider_available(loaned);
  }

  /// Allocates a mutable SHM buffer of the given [size].
  ///
  /// Returns null if allocation fails (e.g., not enough space).
  ShmMutBuffer? alloc(int size) {
    _ensureOpen();
    final loaned = ffi_bindings.zd_shm_provider_loan(_ptr.cast());
    final bufSize = ffi_bindings.zd_shm_mut_sizeof();
    final Pointer<Void> bufPtr = calloc.allocate(bufSize);

    final rc = ffi_bindings.zd_shm_provider_alloc(loaned, bufPtr.cast(), size);
    if (rc != 0) {
      calloc.free(bufPtr);
      return null;
    }

    return ShmMutBuffer.fromNative(bufPtr);
  }

  /// Allocates a mutable SHM buffer with GC + defrag + blocking strategy.
  ///
  /// Returns null if allocation fails.
  ShmMutBuffer? allocGcDefragBlocking(int size) {
    _ensureOpen();
    final loaned = ffi_bindings.zd_shm_provider_loan(_ptr.cast());
    final bufSize = ffi_bindings.zd_shm_mut_sizeof();
    final Pointer<Void> bufPtr = calloc.allocate(bufSize);

    final rc = ffi_bindings.zd_shm_provider_alloc_gc_defrag_blocking(
      loaned,
      bufPtr.cast(),
      size,
    );
    if (rc != 0) {
      calloc.free(bufPtr);
      return null;
    }

    return ShmMutBuffer.fromNative(bufPtr);
  }

  /// Releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    ffi_bindings.zd_shm_provider_drop(_ptr.cast());
    calloc.free(_ptr);
  }
}
