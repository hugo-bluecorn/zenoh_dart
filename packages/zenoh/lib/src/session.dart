import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'config.dart';
import 'congestion_control.dart';
import 'encoding.dart';
import 'exceptions.dart';
import 'id.dart';
import 'keyexpr.dart';
import 'bindings.dart' as ffi_bindings;
import 'native_lib.dart';
import 'priority.dart';
import 'publisher.dart';
import 'subscriber.dart';

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
    ensureInitialized();
    final size = ffi_bindings.zd_session_sizeof();
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

    final rc = ffi_bindings.zd_open_session(
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
    ffi_bindings.zd_close_session(_ptr.cast());
    calloc.free(_ptr);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Session has been closed');
  }

  /// Returns the [ZenohId] of this session.
  ///
  /// Throws [StateError] if the session has been closed.
  ZenohId get zid {
    _ensureOpen();
    final outId = calloc<Uint8>(16);
    try {
      final loanedSession = ffi_bindings.zd_session_loan(_ptr.cast());
      ffi_bindings.zd_info_zid(loanedSession, outId);
      return ZenohId(Uint8List.fromList(outId.asTypedList(16)));
    } finally {
      calloc.free(outId);
    }
  }

  /// Collects ZenohIds using a native info function that fills a buffer.
  List<ZenohId> _collectZids(
    int Function(Pointer<Opaque>, Pointer<Uint8>, int) nativeCall,
  ) {
    _ensureOpen();
    const maxCount = 64;
    final outIds = calloc<Uint8>(maxCount * 16);
    try {
      final loanedSession = ffi_bindings.zd_session_loan(_ptr.cast());
      final count = nativeCall(loanedSession, outIds, maxCount);
      final allBytes = outIds.asTypedList(count * 16);
      return [
        for (var i = 0; i < count; i++)
          ZenohId(Uint8List.fromList(allBytes.sublist(i * 16, (i + 1) * 16))),
      ];
    } finally {
      calloc.free(outIds);
    }
  }

  /// Returns the [ZenohId]s of all connected routers.
  ///
  /// May return an empty list if no router is connected (e.g., in peer mode).
  ///
  /// Throws [StateError] if the session has been closed.
  List<ZenohId> routersZid() => _collectZids(ffi_bindings.zd_info_routers_zid);

  /// Returns the [ZenohId]s of all connected peers.
  ///
  /// May return an empty list if no peer is connected.
  ///
  /// Throws [StateError] if the session has been closed.
  List<ZenohId> peersZid() => _collectZids(ffi_bindings.zd_info_peers_zid);

  /// Executes [action] with a loaned session and a loaned key expression,
  /// guaranteeing cleanup of the key expression in all cases.
  void _withKeyExpr(
    String keyExpr,
    void Function(Pointer<Void> loanedSession, Pointer<Void> loanedKe) action,
  ) {
    _ensureOpen();
    final ke = KeyExpr(keyExpr);
    try {
      final loanedSession =
          ffi_bindings.zd_session_loan(_ptr.cast()) as Pointer<Void>;
      final loanedKe =
          ffi_bindings.zd_view_keyexpr_loan(ke.nativePtr.cast()) as Pointer<Void>;
      action(loanedSession, loanedKe);
    } finally {
      ke.dispose();
    }
  }

  /// Publishes a string [value] on the given [keyExpr].
  ///
  /// Throws [ZenohException] if the key expression is invalid or the put fails.
  /// Throws [StateError] if the session has been closed.
  void put(String keyExpr, String value) {
    _withKeyExpr(keyExpr, (loanedSession, loanedKe) {
      final payload = ZBytes.fromString(value);
      final rc = ffi_bindings.zd_put(
        loanedSession.cast(),
        loanedKe.cast(),
        payload.nativePtr.cast(),
      );
      payload.markConsumed();
      if (rc != 0) {
        throw ZenohException('Put failed', rc);
      }
    });
  }

  /// Publishes a [ZBytes] [payload] on the given [keyExpr].
  ///
  /// The payload is consumed by this call and must not be reused.
  ///
  /// Throws [ZenohException] if the key expression is invalid or the put fails.
  /// Throws [StateError] if the session has been closed, or the payload
  /// has been disposed or already consumed.
  void putBytes(String keyExpr, ZBytes payload) {
    _ensureOpen();
    // Validate payload state before allocating KeyExpr
    final payloadPtr = payload.nativePtr;
    _withKeyExpr(keyExpr, (loanedSession, loanedKe) {
      final rc = ffi_bindings.zd_put(
        loanedSession.cast(),
        loanedKe.cast(),
        payloadPtr.cast(),
      );
      payload.markConsumed();
      if (rc != 0) {
        throw ZenohException('Put failed', rc);
      }
    });
  }

  /// Deletes a resource on the given [keyExpr].
  ///
  /// Throws [ZenohException] if the key expression is invalid or the delete fails.
  /// Throws [StateError] if the session has been closed.
  void deleteResource(String keyExpr) {
    _withKeyExpr(keyExpr, (loanedSession, loanedKe) {
      final rc = ffi_bindings.zd_delete(loanedSession.cast(), loanedKe.cast());
      if (rc != 0) {
        throw ZenohException('Delete failed', rc);
      }
    });
  }

  /// Declares a publisher on the given [keyExpr].
  ///
  /// Returns a [Publisher] that can efficiently publish multiple messages
  /// to the same key expression. Call [Publisher.close] when done.
  ///
  /// Throws [ZenohException] if the key expression is invalid.
  /// Throws [StateError] if the session has been closed.
  Publisher declarePublisher(
    String keyExpr, {
    Encoding? encoding,
    CongestionControl congestionControl = CongestionControl.block,
    Priority priority = Priority.data,
    bool enableMatchingListener = false,
  }) {
    _ensureOpen();
    final ke = KeyExpr(keyExpr);
    try {
      final loanedSession =
          ffi_bindings.zd_session_loan(_ptr.cast()) as Pointer<Void>;
      final loanedKe =
          ffi_bindings.zd_view_keyexpr_loan(ke.nativePtr.cast()) as Pointer<Void>;
      return Publisher.declare(
        loanedSession,
        loanedKe,
        encoding: encoding,
        congestionControl: congestionControl,
        priority: priority,
        enableMatchingListener: enableMatchingListener,
      );
    } finally {
      ke.dispose();
    }
  }

  /// Declares a subscriber on the given [keyExpr].
  ///
  /// Returns a [Subscriber] whose [Subscriber.stream] delivers [Sample]s.
  /// Call [Subscriber.close] when done to undeclare and release resources.
  ///
  /// Throws [ZenohException] if the key expression is invalid.
  /// Throws [StateError] if the session has been closed.
  Subscriber declareSubscriber(String keyExpr) {
    _ensureOpen();
    final ke = KeyExpr(keyExpr);
    try {
      final loanedSession =
          ffi_bindings.zd_session_loan(_ptr.cast()) as Pointer<Void>;
      final loanedKe =
          ffi_bindings.zd_view_keyexpr_loan(ke.nativePtr.cast()) as Pointer<Void>;
      return Subscriber.declare(loanedSession, loanedKe);
    } finally {
      ke.dispose();
    }
  }
}
