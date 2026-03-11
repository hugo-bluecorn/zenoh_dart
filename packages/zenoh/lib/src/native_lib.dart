import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'bindings.dart' as ffi_bindings;

bool _initialized = false;

/// Pre-loads native libraries via DynamicLibrary.open() before @Native triggers.
///
/// @Native annotations use dlopen with NoActiveIsolateScope (thread detached
/// from isolate) and resolve symbols lazily on background threads. This causes
/// crashes when two Dart processes connect via zenoh TCP. Pre-loading via
/// DynamicLibrary.open() puts the library in the process's global handle table
/// eagerly on the main thread. When @Native later calls dlopen(), the OS
/// returns the same handle (refcount increment).
///
/// Loading libzenoh_dart.so also transitively loads libzenohc.so via DT_NEEDED
/// (RPATH=$ORIGIN ensures the OS linker finds it in the same directory).
void _preloadNativeLibraries() {
  final libPath = _resolveLibraryPath('libzenoh_dart.so');
  if (libPath != null) {
    DynamicLibrary.open(libPath);
  }
}

/// Resolves the absolute path to a native library bundled by the build hook.
///
/// Build hooks place libraries in `.dart_tool/lib/` relative to the package
/// root. We find the package root via Isolate.resolvePackageUriSync().
String? _resolveLibraryPath(String libraryName) {
  try {
    final packageUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:zenoh/src/native_lib.dart'),
    );
    if (packageUri != null) {
      // packageUri = file:///...packages/zenoh/lib/src/native_lib.dart
      // Package root = ../../.. from lib/src/
      final packageRoot = packageUri.resolve('../../');
      final libFile = File.fromUri(
        packageRoot.resolve('.dart_tool/lib/$libraryName'),
      );
      if (libFile.existsSync()) return libFile.path;
    }

    // Fallback: try relative to current working directory
    final candidates = <String>[
      '.dart_tool/lib/$libraryName',
      'packages/zenoh/.dart_tool/lib/$libraryName',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file.absolute.path;
    }

    return null;
  } catch (_) {
    return null;
  }
}

/// Ensures the Dart API DL is initialized.
///
/// Must be called before any native port usage (subscribers,
/// publisher matching status). Safe to call multiple times.
void ensureInitialized() {
  if (_initialized) return;
  _preloadNativeLibraries();
  final result = ffi_bindings.zd_init_dart_api_dl(
    NativeApi.initializeApiDLData,
  );
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }
  _initialized = true;
}
