import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'id.dart';
import 'native_lib.dart';
import 'sample.dart';
import 'subscriber.dart';

/// Options for configuring an advanced subscriber.
class AdvancedSubscriberOptions {
  /// Whether to recover historical data on subscription.
  final bool history;

  /// Whether to detect late publishers and recover their history.
  final bool detectLatePublishers;

  /// Whether to enable sample recovery.
  final bool recovery;

  /// Whether to enable last sample miss detection for recovery.
  final bool lastSampleMissDetection;

  /// Period in milliseconds for periodic recovery queries (0 = disabled).
  final int periodicQueriesPeriodMs;

  /// Whether to enable subscriber detection.
  final bool subscriberDetection;

  /// Whether to enable the miss event listener.
  final bool enableMissListener;

  /// Creates advanced subscriber options.
  const AdvancedSubscriberOptions({
    this.history = false,
    this.detectLatePublishers = false,
    this.recovery = false,
    this.lastSampleMissDetection = false,
    this.periodicQueriesPeriodMs = 0,
    this.subscriberDetection = false,
    this.enableMissListener = false,
  });
}

/// Information about missed samples from a source.
class MissEvent {
  /// The ZenohId of the source that missed samples.
  final ZenohId sourceId;

  /// The number of missed samples.
  final int count;

  /// Creates a MissEvent.
  const MissEvent({required this.sourceId, required this.count});
}

/// An advanced subscriber with history recovery and miss detection.
///
/// Wraps `ze_owned_advanced_subscriber_t`. Samples are delivered
/// asynchronously via a [Stream]. Call [close] when done to undeclare
/// the subscriber and release native resources.
class AdvancedSubscriber {
  final Pointer<Void> _ptr;
  final ReceivePort _samplePort;
  final StreamController<Sample> _sampleController;
  final ReceivePort? _missPort;
  final StreamController<MissEvent>? _missController;
  bool _closed = false;

  AdvancedSubscriber._(
    this._ptr,
    this._samplePort,
    this._sampleController,
    this._missPort,
    this._missController,
  );

  /// Creates an advanced subscriber on the given session and key expression.
  ///
  /// This is called internally by [Session.declareAdvancedSubscriber].
  static AdvancedSubscriber declare(
    Pointer<Void> loanedSession,
    Pointer<Void> loanedKe, {
    AdvancedSubscriberOptions options = const AdvancedSubscriberOptions(),
  }) {
    final size = bindings.zd_advanced_subscriber_sizeof();
    final Pointer<Void> ptr = calloc.allocate(size);

    final (samplePort, sampleController) = Subscriber.createSampleChannel();

    final rc = bindings.zd_declare_advanced_subscriber(
      loanedSession.cast(),
      ptr.cast(),
      loanedKe.cast(),
      samplePort.sendPort.nativePort,
      options.history,
      options.detectLatePublishers,
      options.recovery,
      options.lastSampleMissDetection,
      options.periodicQueriesPeriodMs,
      options.subscriberDetection,
    );

    if (rc != 0) {
      samplePort.close();
      sampleController.close();
      calloc.free(ptr);
      throw ZenohException('Failed to declare advanced subscriber', rc);
    }

    ReceivePort? missPort;
    StreamController<MissEvent>? missController;

    if (options.enableMissListener) {
      missPort = ReceivePort();
      missController = StreamController<MissEvent>();

      missPort.listen((dynamic message) {
        if (message is List) {
          final zidBytes = message[0] as Uint8List;
          final count = message[1] as int;
          final sourceId = ZenohId(zidBytes);
          missController!.add(MissEvent(sourceId: sourceId, count: count));
        }
      });

      final loaned = bindings.zd_advanced_subscriber_loan(ptr.cast());
      final missRc = bindings
          .zd_advanced_subscriber_declare_background_sample_miss_listener(
            loaned,
            missPort.sendPort.nativePort,
          );

      if (missRc != 0) {
        missPort.close();
        missController.close();
        samplePort.close();
        sampleController.close();
        bindings.zd_advanced_subscriber_drop(ptr.cast());
        calloc.free(ptr);
        throw ZenohException('Failed to declare miss listener', missRc);
      }
    }

    return AdvancedSubscriber._(
      ptr,
      samplePort,
      sampleController,
      missPort,
      missController,
    );
  }

  /// A stream of [Sample]s received by this advanced subscriber.
  Stream<Sample> get stream => _sampleController.stream;

  /// A stream of [MissEvent]s when samples are missed, or null if the
  /// miss listener was not enabled.
  Stream<MissEvent>? get missEvents => _missController?.stream;

  /// Undeclares the advanced subscriber and releases native resources.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    bindings.zd_advanced_subscriber_drop(_ptr.cast());
    _samplePort.close();
    _sampleController.close();
    _missPort?.close();
    _missController?.close();
    calloc.free(_ptr);
  }
}
