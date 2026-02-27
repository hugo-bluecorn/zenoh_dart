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

  /// Gracefully closes the session and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    bindings.zd_close_session(_ptr.cast());
    calloc.free(_ptr);
  }
}
