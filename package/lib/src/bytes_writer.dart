import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A zenoh bytes writer for assembling raw byte payloads.
///
/// Wraps `z_owned_bytes_writer_t`. Call [finish] to produce a [ZBytes],
/// or [dispose] to release native resources without finishing.
class ZBytesWriter {
  final Pointer<Void> _ptr;
  bool _finished = false;
  bool _disposed = false;

  /// Creates an empty bytes writer.
  ZBytesWriter() : _ptr = _create();

  static Pointer<Void> _create() {
    final size = bindings.zd_bytes_writer_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);
    bindings.zd_bytes_writer_empty(ptr.cast());
    return ptr;
  }

  void _checkState() {
    if (_disposed) throw StateError('ZBytesWriter has been disposed');
    if (_finished) throw StateError('ZBytesWriter has been finished');
  }

  Pointer<Void> _loanMut() {
    final out = calloc<Pointer<Void>>();
    bindings.zd_bytes_writer_loan_mut(_ptr.cast(), out.cast());
    final loaned = out.value;
    calloc.free(out);
    return loaned;
  }

  /// Writes all bytes from [data] into the writer.
  ///
  /// Throws [StateError] if already finished or disposed.
  /// Throws [ZenohException] if the native write fails.
  void writeAll(Uint8List data) {
    _checkState();
    final Pointer<Uint8> nativeBuf = calloc.allocate(data.length);
    try {
      for (var i = 0; i < data.length; i++) {
        nativeBuf[i] = data[i];
      }
      final rc = bindings.zd_bytes_writer_write_all(
        _loanMut().cast(),
        nativeBuf,
        data.length,
      );
      if (rc != 0) throw ZenohException('Failed to write bytes', rc);
    } finally {
      calloc.free(nativeBuf);
    }
  }

  /// Appends owned [bytes] into the writer, consuming them.
  ///
  /// After this call, the [bytes] object is consumed and must not be used.
  ///
  /// Throws [StateError] if already finished or disposed.
  /// Throws [ZenohException] if the native append fails.
  void append(ZBytes bytes) {
    _checkState();
    final rc = bindings.zd_bytes_writer_append(
      _loanMut().cast(),
      bytes.nativePtr.cast(),
    );
    if (rc != 0) throw ZenohException('Failed to append bytes', rc);
    bytes.markConsumed();
  }

  /// Finishes the writer and returns the produced [ZBytes].
  ///
  /// The writer is consumed by this call. After finishing,
  /// no further operations are allowed.
  ///
  /// Throws [StateError] if already finished or disposed.
  ZBytes finish() {
    _checkState();
    _finished = true;
    final Pointer<Void> bytesPtr = calloc.allocate(bindings.zd_bytes_sizeof());
    bindings.zd_bytes_writer_finish(_ptr.cast(), bytesPtr.cast());
    calloc.free(_ptr);
    return ZBytes.fromNative(bytesPtr);
  }

  /// Releases native resources held by this writer.
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
    bindings.zd_bytes_writer_drop(_ptr.cast());
    calloc.free(_ptr);
  }
}
