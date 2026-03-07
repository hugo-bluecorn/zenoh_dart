import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'config.dart';
import 'hello.dart';
import 'id.dart';
import 'native_lib.dart';
import 'whatami.dart';

/// Top-level zenoh utilities.
///
/// Provides static methods for global zenoh initialization that must be
/// called before opening sessions.
class Zenoh {
  Zenoh._(); // prevent instantiation

  /// Initializes the zenoh logger from the `RUST_LOG` environment variable,
  /// falling back to [fallback] if `RUST_LOG` is not set.
  ///
  /// Must be called **before** [Session.open] for logging to take effect.
  /// This is a one-time initialization -- subsequent calls are ignored by
  /// the underlying runtime.
  ///
  /// Filter syntax follows the Rust `env_logger` format:
  /// - `"error"` -- errors only (recommended for production)
  /// - `"warn"` -- warnings and errors
  /// - `"info"` -- informational messages
  /// - `"debug"` -- debug-level detail
  /// - `"trace"` -- maximum verbosity
  ///
  /// See: https://docs.rs/env_logger/latest/env_logger/
  static void initLog(String fallback) {
    final cStr = fallback.toNativeUtf8();
    try {
      bindings.zd_init_log(cStr.cast<Char>());
    } finally {
      calloc.free(cStr);
    }
  }

  /// Scouts for zenoh entities on the network.
  ///
  /// Returns a list of [Hello] messages from discovered entities.
  /// The scouting runs for [timeoutMs] milliseconds (default 1000).
  ///
  /// If [config] is provided, it is consumed by the scout call and must
  /// not be reused. If [config] is null, a default configuration is used.
  ///
  /// The [what] parameter specifies which entity types to scout for
  /// (default 3 = routers + peers). Uses zenoh-c bitmask values:
  /// 1=router, 2=peer, 4=client.
  ///
  /// Throws [StateError] if [config] has been consumed or disposed.
  static Future<List<Hello>> scout({
    Config? config,
    int timeoutMs = 1000,
    int what = 3,
  }) async {
    // Validate config state before proceeding
    int configAddr;
    if (config != null) {
      // This will throw StateError if consumed or disposed
      configAddr = config.nativePtr.address;
    } else {
      configAddr = 0;
    }

    final receivePort = ReceivePort();
    final hellos = <Hello>[];
    final completer = Completer<List<Hello>>();

    receivePort.listen((dynamic message) {
      if (message == null) {
        // Null sentinel from C -- scouting complete
        completer.complete(hellos);
        receivePort.close();
      } else if (message is List) {
        final zidBytes = message[0] as Uint8List;
        final whatami = message[1] as int;
        final locatorsStr = message[2] as String;
        hellos.add(Hello(
          zid: ZenohId(zidBytes),
          whatami: WhatAmI.fromInt(whatami),
          locators:
              locatorsStr.isEmpty ? <String>[] : locatorsStr.split(';'),
        ));
      }
    });

    final nativePort = receivePort.sendPort.nativePort;

    // Mark config as consumed before the call
    if (config != null) {
      config.markConsumed();
    }

    // Call zd_scout synchronously. It blocks for timeoutMs but posts
    // Hello messages to the NativePort asynchronously. The messages
    // are queued and will be processed when we await the completer.
    final cfgPtr = configAddr != 0
        ? Pointer<Void>.fromAddress(configAddr)
        : nullptr;
    bindings.zd_scout(cfgPtr.cast(), nativePort, timeoutMs, what);

    return completer.future;
  }
}
