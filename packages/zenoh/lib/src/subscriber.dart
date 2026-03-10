import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'bindings.dart' as ffi_bindings;
import 'sample.dart';

/// A zenoh subscriber that receives samples on a key expression.
///
/// Wraps `z_owned_subscriber_t`. Samples are delivered asynchronously
/// via a [Stream]. Call [close] when done to undeclare the subscriber
/// and release native resources.
class Subscriber {
  final Pointer<Void> _ptr;
  final ReceivePort _receivePort;
  final StreamController<Sample> _controller;
  bool _closed = false;

  Subscriber._(this._ptr, this._receivePort, this._controller);

  /// Creates a subscriber on the given session and key expression.
  ///
  /// This is called internally by [Session.declareSubscriber].
  static Subscriber declare(
    Pointer<Void> loanedSession,
    Pointer<Void> loanedKe,
  ) {
    final size = ffi_bindings.zd_subscriber_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);

    final receivePort = ReceivePort();
    final controller = StreamController<Sample>();

    receivePort.listen((dynamic message) {
      if (message is List) {
        final keyExpr = message[0] as String;
        final payloadBytes = message[1] as Uint8List;
        final kind = message[2] as int;
        final attachmentBytes = message[3] as Uint8List?;
        final encoding = message.length > 4 ? message[4] as String? : null;

        final sample = Sample(
          keyExpr: keyExpr,
          payload: utf8.decode(payloadBytes),
          payloadBytes: payloadBytes,
          kind: kind == 0 ? SampleKind.put : SampleKind.delete,
          attachment: attachmentBytes != null
              ? utf8.decode(attachmentBytes)
              : null,
          encoding: encoding,
        );
        controller.add(sample);
      }
    });

    final rc = ffi_bindings.zd_declare_subscriber(
      loanedSession.cast(),
      ptr.cast(),
      loanedKe.cast(),
      receivePort.sendPort.nativePort,
    );

    if (rc != 0) {
      receivePort.close();
      controller.close();
      calloc.free(ptr);
      throw ZenohException('Failed to declare subscriber', rc);
    }

    return Subscriber._(ptr, receivePort, controller);
  }

  /// A stream of [Sample]s received by this subscriber.
  Stream<Sample> get stream => _controller.stream;

  /// Undeclares the subscriber and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    ffi_bindings.zd_subscriber_drop(_ptr.cast());
    _receivePort.close();
    _controller.close();
    calloc.free(_ptr);
  }
}
