import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'encoding.dart';
import 'exceptions.dart';
import 'native_lib.dart';

/// A received query on a queryable key expression.
///
/// Wraps a heap-allocated `z_owned_query_t`. The query holds a cloned
/// reference to the original query from the callback. Call [dispose]
/// when done to release native resources (even if no reply was sent).
class Query {
  final int _handle;
  bool _disposed = false;

  /// The key expression of this query.
  final String keyExpr;

  /// The query parameters (selector portion after '?'). Empty if none.
  final String parameters;

  /// The optional payload attached to this query.
  final Uint8List? payloadBytes;

  /// Creates a Query from NativePort message data.
  ///
  /// This is called internally by [Queryable] stream handler.
  Query({
    required int handle,
    required this.keyExpr,
    required this.parameters,
    this.payloadBytes,
  }) : _handle = handle;

  /// The native pointer handle for this query (used by reply methods).
  int get handle {
    _ensureNotDisposed();
    return _handle;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Query has been disposed');
    }
  }

  /// Sends a reply to this query with a string value.
  ///
  /// The [keyExpr] should match the queryable's key expression.
  /// Optionally specify an [encoding] for the payload.
  ///
  /// Throws [StateError] if the query has been disposed.
  /// Throws [ZenohException] if the reply fails.
  void reply(String keyExpr, String value, {Encoding? encoding}) {
    _ensureNotDisposed();
    final zbytes = ZBytes.fromString(value);
    replyBytes(keyExpr, zbytes, encoding: encoding);
  }

  /// Sends a reply to this query with a [ZBytes] payload.
  ///
  /// The [keyExpr] should match the queryable's key expression.
  /// The [payload] is consumed by this call (ownership transferred to zenoh).
  /// Optionally specify an [encoding] for the payload.
  ///
  /// Throws [StateError] if the query has been disposed.
  /// Throws [ZenohException] if the reply fails.
  void replyBytes(String keyExpr, ZBytes payload, {Encoding? encoding}) {
    _ensureNotDisposed();

    final keyExprNative = keyExpr.toNativeUtf8();

    Pointer<Utf8> encodingNative = nullptr;
    if (encoding != null) {
      encodingNative = encoding.mimeType.toNativeUtf8();
    }

    try {
      final rc = bindings.zd_query_reply(
        Pointer.fromAddress(_handle).cast(),
        keyExprNative.cast(),
        payload.nativePtr.cast(),
        encoding != null ? encodingNative.cast() : nullptr,
      );

      if (rc != 0) {
        throw ZenohException('Failed to reply to query', rc);
      }

      payload.markConsumed();
    } finally {
      calloc.free(keyExprNative);
      if (encoding != null) {
        calloc.free(encodingNative);
      }
    }
  }

  /// Releases the native query resources.
  ///
  /// Must be called even if no reply was sent. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    bindings.zd_query_drop(Pointer.fromAddress(_handle).cast());
  }
}
