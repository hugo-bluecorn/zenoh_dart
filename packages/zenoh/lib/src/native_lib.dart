import 'dart:ffi';
import 'dart:io';

import 'bindings.dart';

/// Loads the zenoh_dart native shared library.
///
/// The library name varies by platform:
/// - Linux/Android: `libzenoh_dart.so`
/// - macOS/iOS: `libzenoh_dart.dylib`
/// - Windows: `zenoh_dart.dll`
DynamicLibrary openZenohDartLibrary() {
  if (Platform.isLinux || Platform.isAndroid) {
    return DynamicLibrary.open('libzenoh_dart.so');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('libzenoh_dart.dylib');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('zenoh_dart.dll');
  }
  throw UnsupportedError(
    'Unsupported platform: ${Platform.operatingSystem}',
  );
}

/// Lazy singleton for the FFI bindings.
///
/// On first access, loads the native library and initializes the
/// Dart API DL (required for native ports / SendPort usage).
ZenohDartBindings get bindings => _bindings ??= _initBindings();

ZenohDartBindings? _bindings;

ZenohDartBindings _initBindings() {
  final lib = openZenohDartLibrary();
  final b = ZenohDartBindings(lib);

  // Initialize Dart API DL -- must succeed before any native port usage.
  final result = b.zd_init_dart_api_dl(NativeApi.initializeApiDLData);
  if (result != 0) {
    throw StateError(
      'Failed to initialize Dart API DL (code: $result)',
    );
  }

  return b;
}
