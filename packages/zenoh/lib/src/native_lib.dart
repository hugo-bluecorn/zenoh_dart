import 'dart:ffi';

import 'bindings.dart' as ffi_bindings;

bool _initialized = false;

/// Ensures the Dart API DL is initialized.
///
/// Must be called before any native port usage (subscribers,
/// publisher matching status). Safe to call multiple times.
void ensureInitialized() {
  if (_initialized) return;
  final result = ffi_bindings.zd_init_dart_api_dl(
    NativeApi.initializeApiDLData,
  );
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }
  _initialized = true;
}
