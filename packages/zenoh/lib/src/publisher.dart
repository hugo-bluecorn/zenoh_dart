import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'bytes.dart';
import 'congestion_control.dart';
import 'encoding.dart';
import 'exceptions.dart';
import 'native_lib.dart';
import 'priority.dart';

/// A zenoh publisher for efficiently publishing multiple messages on a
/// single key expression.
///
/// Wraps `z_owned_publisher_t`. Call [close] when done to undeclare the
/// publisher and release native resources.
class Publisher {
  final Pointer<Void> _ptr;
  bool _closed = false;
  final ReceivePort? _matchingPort;
  final StreamController<bool>? _matchingController;

  Publisher._(this._ptr, this._matchingPort, this._matchingController);

  /// Creates a publisher on the given session and key expression.
  ///
  /// This is called internally by [Session.declarePublisher].
  static Publisher declare(
    Pointer<Void> loanedSession,
    Pointer<Void> loanedKe, {
    Encoding? encoding,
    CongestionControl congestionControl = CongestionControl.block,
    Priority priority = Priority.data,
    bool enableMatchingListener = false,
  }) {
    final size = bindings.zd_publisher_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);

    final encodingStr =
        encoding != null ? encoding.mimeType.toNativeUtf8() : nullptr;

    try {
      final rc = bindings.zd_declare_publisher(
        loanedSession.cast(),
        ptr.cast(),
        loanedKe.cast(),
        encodingStr.cast(),
        congestionControl.index,
        priority.index + 1, // zenoh-c uses 1-indexed priority
      );

      if (rc != 0) {
        calloc.free(ptr);
        throw ZenohException('Failed to declare publisher', rc);
      }
    } finally {
      if (encodingStr != nullptr) malloc.free(encodingStr);
    }

    ReceivePort? matchingPort;
    StreamController<bool>? matchingController;

    if (enableMatchingListener) {
      matchingPort = ReceivePort();
      matchingController = StreamController<bool>();

      matchingPort.listen((dynamic message) {
        if (message is int) {
          matchingController!.add(message != 0);
        }
      });

      final loaned = bindings.zd_publisher_loan(ptr.cast());
      final mlRc = bindings.zd_publisher_declare_background_matching_listener(
        loaned,
        matchingPort.sendPort.nativePort,
      );

      if (mlRc != 0) {
        matchingPort.close();
        matchingController.close();
        bindings.zd_publisher_drop(ptr.cast());
        calloc.free(ptr);
        throw ZenohException(
          'Failed to declare matching listener',
          mlRc,
        );
      }
    }

    return Publisher._(ptr, matchingPort, matchingController);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Publisher has been closed');
  }

  /// The key expression this publisher is declared on.
  String get keyExpr {
    _ensureOpen();
    final loaned = bindings.zd_publisher_loan(_ptr.cast());
    final loanedKe = bindings.zd_publisher_keyexpr(loaned);
    final viewStrSize = bindings.zd_view_string_sizeof();
    final Pointer<Void> viewStr = calloc.allocate(viewStrSize);
    bindings.zd_keyexpr_as_view_string(loanedKe, viewStr.cast());
    final data = bindings.zd_view_string_data(viewStr.cast());
    final len = bindings.zd_view_string_len(viewStr.cast());
    final result = data.cast<Utf8>().toDartString(length: len);
    calloc.free(viewStr);
    return result;
  }

  /// Publishes a string [value] through this publisher.
  ///
  /// Optionally override the [encoding] for this specific put.
  /// An optional [attachment] can be included (consumed by this call).
  void put(String value, {Encoding? encoding, ZBytes? attachment}) {
    _ensureOpen();
    final loaned = bindings.zd_publisher_loan(_ptr.cast());
    final payload = ZBytes.fromString(value);

    final encodingStr =
        encoding != null ? encoding.mimeType.toNativeUtf8() : nullptr;
    final attachmentPtr =
        attachment != null ? attachment.nativePtr : nullptr;

    try {
      final rc = bindings.zd_publisher_put(
        loaned,
        payload.nativePtr.cast(),
        encodingStr.cast(),
        attachmentPtr.cast(),
      );

      payload.markConsumed();
      if (attachment != null) attachment.markConsumed();

      if (rc != 0) {
        throw ZenohException('Publisher put failed', rc);
      }
    } finally {
      if (encodingStr != nullptr) malloc.free(encodingStr);
    }
  }

  /// Publishes [ZBytes] [payload] through this publisher.
  ///
  /// The payload is consumed by this call and must not be reused.
  /// An optional [attachment] can be included (consumed by this call).
  void putBytes(ZBytes payload, {Encoding? encoding, ZBytes? attachment}) {
    _ensureOpen();
    final loaned = bindings.zd_publisher_loan(_ptr.cast());
    final payloadPtr = payload.nativePtr;

    final encodingStr =
        encoding != null ? encoding.mimeType.toNativeUtf8() : nullptr;
    final attachmentPtr =
        attachment != null ? attachment.nativePtr : nullptr;

    try {
      final rc = bindings.zd_publisher_put(
        loaned,
        payloadPtr.cast(),
        encodingStr.cast(),
        attachmentPtr.cast(),
      );

      payload.markConsumed();
      if (attachment != null) attachment.markConsumed();

      if (rc != 0) {
        throw ZenohException('Publisher put failed', rc);
      }
    } finally {
      if (encodingStr != nullptr) malloc.free(encodingStr);
    }
  }

  /// Sends a DELETE through this publisher.
  void deleteResource() {
    _ensureOpen();
    final loaned = bindings.zd_publisher_loan(_ptr.cast());
    final rc = bindings.zd_publisher_delete(loaned);
    if (rc != 0) {
      throw ZenohException('Publisher delete failed', rc);
    }
  }

  /// Returns whether any subscribers currently match this publisher's
  /// key expression.
  bool hasMatchingSubscribers() {
    _ensureOpen();
    final loaned = bindings.zd_publisher_loan(_ptr.cast());
    final Pointer<Int> matching = calloc<Int>();
    try {
      final rc = bindings.zd_publisher_get_matching_status(loaned, matching);
      if (rc != 0) {
        throw ZenohException('Failed to get matching status', rc);
      }
      return matching.value != 0;
    } finally {
      calloc.free(matching);
    }
  }

  /// A stream of matching status changes, or null if the matching listener
  /// was not enabled when the publisher was declared.
  Stream<bool>? get matchingStatus => _matchingController?.stream;

  /// Undeclares the publisher and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    bindings.zd_publisher_drop(_ptr.cast());
    _matchingPort?.close();
    _matchingController?.close();
    calloc.free(_ptr);
  }
}
