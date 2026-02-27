import 'dart:ffi';
import 'dart:io';

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
