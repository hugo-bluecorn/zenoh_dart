import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// Initializes the zenoh_dart native library via @Native annotations.
///
/// Calls `zd_init_dart_api_dl` to initialize the Dart API DL, and
/// `zd_init_log` with the 'error' log level.
///
/// Returns `true` on success, `false` if Dart API DL initialization fails.
bool initZenohDart() {
  final result = zdInitDartApiDl(NativeApi.initializeApiDLData);
  if (result != 0) return false;

  final filter = 'error'.toNativeUtf8();
  try {
    zdInitLog(filter);
  } finally {
    calloc.free(filter);
  }

  return true;
}
