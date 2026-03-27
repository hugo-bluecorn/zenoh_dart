import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_lib.dart';

/// A liveliness token that advertises the session's presence on a key
/// expression for as long as it remains undeclared.
///
/// Wraps `z_owned_liveliness_token_t`. Call [close] when done to undeclare
/// the token and release native resources.
class LivelinessToken {
  final Pointer<Uint8> _ptr;
  final String _keyExpr;
  bool _closed = false;

  LivelinessToken._(this._ptr, this._keyExpr);

  /// Declares a liveliness token on the given session and key expression.
  ///
  /// This is called internally by [Session.declareLivelinessToken].
  static LivelinessToken declare(Pointer<Void> loanedSession, String keyExpr) {
    final size = bindings.zd_liveliness_token_sizeof();
    final Pointer<Uint8> ptr = calloc<Uint8>(size);

    final keyExprNative = keyExpr.toNativeUtf8();

    try {
      final rc = bindings.zd_liveliness_declare_token(
        ptr,
        loanedSession.cast(),
        keyExprNative.cast(),
      );

      if (rc != 0) {
        calloc.free(ptr);
        throw ZenohException('Failed to declare liveliness token', rc);
      }
    } finally {
      calloc.free(keyExprNative);
    }

    return LivelinessToken._(ptr, keyExpr);
  }

  /// The key expression this liveliness token is declared on.
  String get keyExpr => _keyExpr;

  /// Undeclares the liveliness token and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    bindings.zd_liveliness_token_drop(_ptr);
    calloc.free(_ptr);
  }
}
