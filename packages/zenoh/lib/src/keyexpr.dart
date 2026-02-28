import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_lib.dart';

/// A Zenoh key expression.
///
/// Wraps `z_view_keyexpr_t`. The view borrows a native C string that is
/// allocated by the constructor and freed by [dispose].
///
/// Must be [dispose]d when no longer needed to release native memory.
class KeyExpr {
  final Pointer<Void> _kePtr;
  final Pointer<Utf8> _nativeStr;
  bool _disposed = false;

  /// Creates a [KeyExpr] from the given key expression string.
  ///
  /// Throws [ZenohException] if [expr] is not a valid key expression
  /// (e.g., empty string).
  KeyExpr(String expr)
    : _kePtr = calloc.allocate(bindings.zd_view_keyexpr_sizeof()),
      _nativeStr = expr.toNativeUtf8() {
    final rc = bindings.zd_view_keyexpr_from_str(
      _kePtr.cast(),
      _nativeStr.cast(),
    );
    if (rc != 0) {
      malloc.free(_nativeStr);
      calloc.free(_kePtr);
      throw ZenohException('Invalid key expression: "$expr"', rc);
    }
  }

  /// Returns the key expression as a Dart string.
  ///
  /// Throws [StateError] if this [KeyExpr] has been disposed.
  String get value {
    _ensureNotDisposed();
    final Pointer<Void> viewStr = calloc.allocate(
      bindings.zd_view_string_sizeof(),
    );
    bindings.zd_keyexpr_as_view_string(
      bindings.zd_view_keyexpr_loan(_kePtr.cast()),
      viewStr.cast(),
    );
    final data = bindings.zd_view_string_data(viewStr.cast());
    final len = bindings.zd_view_string_len(viewStr.cast());
    final result = data.cast<Utf8>().toDartString(length: len);
    calloc.free(viewStr);
    return result;
  }

  /// Releases native resources held by this key expression.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    malloc.free(_nativeStr);
    calloc.free(_kePtr);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('KeyExpr has been disposed');
  }
}
