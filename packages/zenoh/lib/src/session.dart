import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'config.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A Zenoh session.
///
/// Wraps `z_owned_session_t`. Use [Session.open] to create a session,
/// optionally passing a [Config]. Call [close] when done to gracefully
/// shut down the session and release native resources.
class Session {
  final Pointer<Void> _ptr;
  bool _closed = false;

  Session._(this._ptr);

  /// Opens a Zenoh session.
  ///
  /// If [config] is provided, it is consumed by the session and must not
  /// be reused or disposed by the caller. If [config] is null, a default
  /// configuration is created internally.
  ///
  /// Throws [ZenohException] if the session cannot be opened.
  static Session open({Config? config}) {
    final size = bindings.zd_session_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);

    Config effectiveConfig;
    bool ownsConfig;
    if (config != null) {
      effectiveConfig = config;
      ownsConfig = false;
    } else {
      effectiveConfig = Config();
      ownsConfig = true;
    }

    final rc = bindings.zd_open_session(
      ptr.cast(),
      effectiveConfig.nativePtr.cast(),
    );

    // Mark user-provided config as consumed regardless of success/failure,
    // because z_config_move already consumed the native pointer.
    if (config != null) {
      config.markConsumed();
    }

    if (rc != 0) {
      calloc.free(ptr);
      if (ownsConfig) effectiveConfig.dispose();
      throw ZenohException('Failed to open session', rc);
    }

    return Session._(ptr);
  }

  /// Publishes a string [value] on the given [keyExpr].
  ///
  /// Creates a [ZBytes] payload internally from [value] and publishes it.
  /// The key expression is validated before sending.
  ///
  /// Throws [StateError] if the session has been closed.
  /// Throws [ZenohException] if [keyExpr] is invalid or the put fails.
  void put(String keyExpr, String value) {
    _ensureOpen();

    // Validate key expression
    final Pointer<Void> kePtr = calloc.allocate(
      bindings.zd_view_keyexpr_sizeof(),
    );
    final nativeKeyExpr = keyExpr.toNativeUtf8();

    final keRc = bindings.zd_view_keyexpr_from_str(
      kePtr.cast(),
      nativeKeyExpr.cast(),
    );
    if (keRc != 0) {
      malloc.free(nativeKeyExpr);
      calloc.free(kePtr);
      throw ZenohException('Invalid key expression: "$keyExpr"', keRc);
    }

    // Create bytes payload from string
    final Pointer<Void> bytesPtr = calloc.allocate(
      bindings.zd_bytes_sizeof(),
    );
    final nativeValue = value.toNativeUtf8();
    final bytesRc = bindings.zd_bytes_copy_from_str(
      bytesPtr.cast(),
      nativeValue.cast(),
    );
    malloc.free(nativeValue);

    if (bytesRc != 0) {
      malloc.free(nativeKeyExpr);
      calloc.free(kePtr);
      calloc.free(bytesPtr);
      throw ZenohException('Failed to create payload', bytesRc);
    }

    // Perform the put
    try {
      final loanedSession = bindings.zd_session_loan(_ptr.cast());
      final loanedKe = bindings.zd_view_keyexpr_loan(kePtr.cast());
      final putRc = bindings.zd_put(loanedSession, loanedKe, bytesPtr.cast());
      if (putRc != 0) {
        throw ZenohException('Failed to put', putRc);
      }
    } finally {
      // Clean up keyexpr resources (bytes are consumed by zd_put)
      malloc.free(nativeKeyExpr);
      calloc.free(kePtr);
      calloc.free(bytesPtr);
    }
  }

  /// Gracefully closes the session and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    bindings.zd_close_session(_ptr.cast());
    calloc.free(_ptr);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Session has been closed');
  }
}
