import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native_lib.dart';

/// A Zenoh configuration.
///
/// Wraps `z_owned_config_t`. Use the default constructor for default
/// configuration, then call [insertJson5] to customise settings.
///
/// Must be [dispose]d when no longer needed to release native memory.
/// If passed to `Session.open`, the config is consumed and must not be
/// reused or disposed by the caller.
class Config {
  final Pointer<Void> _ptr;
  bool _disposed = false;

  // Internal: set by Session.open after consuming the config.
  bool _consumed = false;

  /// Creates a default Zenoh configuration.
  ///
  /// Throws [ZenohException] if the native config creation fails.
  Config() : _ptr = calloc.allocate(bindings.zd_config_sizeof()) {
    final rc = bindings.zd_config_default(_ptr.cast());
    if (rc != 0) {
      calloc.free(_ptr);
      throw ZenohException('Failed to create default config', rc);
    }
  }

  /// Inserts a JSON5 value at the given configuration key path.
  ///
  /// JSON5 string values require inner quotes, e.g.:
  /// ```dart
  /// config.insertJson5('mode', '"peer"');
  /// ```
  ///
  /// Throws [ZenohException] if the key is invalid or the value is rejected.
  /// Throws [StateError] if the config has been disposed or consumed.
  void insertJson5(String key, String value) {
    _ensureNotDisposed();
    _ensureNotConsumed();
    final nativeKey = key.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      final rc = bindings.zd_config_insert_json5(
        _ptr.cast(),
        nativeKey.cast(),
        nativeValue.cast(),
      );
      if (rc != 0) {
        throw ZenohException(
          'Failed to insert config value for key "$key"',
          rc,
        );
      }
    } finally {
      malloc.free(nativeKey);
      malloc.free(nativeValue);
    }
  }

  /// Releases native resources held by this configuration.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  /// Throws [StateError] if the config has been consumed by Session.open.
  void dispose() {
    if (_disposed) return;
    _ensureNotConsumed();
    _disposed = true;
    bindings.zd_config_drop(_ptr.cast());
    calloc.free(_ptr);
  }

  /// Internal: returns the native pointer for use by Session.open.
  Pointer<Void> get nativePtr {
    _ensureNotDisposed();
    _ensureNotConsumed();
    return _ptr;
  }

  /// Internal: called by Session.open after consuming the config.
  void markConsumed() {
    _consumed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('Config has been disposed');
  }

  void _ensureNotConsumed() {
    if (_consumed) throw StateError('Config has been consumed by Session.open');
  }
}
