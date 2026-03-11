import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'bindings.dart';

bool _initialized = false;
late ZenohDartBindings _bindings;

/// Returns the singleton [ZenohDartBindings] instance.
///
/// The bindings are backed by [DynamicLibrary.open] which loads the library
/// eagerly on the main thread. This avoids the Dart VM's `@Native` loading
/// path which uses `NoActiveIsolateScope` (thread-isolate detachment during
/// dlopen) and causes tokio waker vtable crashes when two Dart processes
/// connect via zenoh TCP.
///
/// Auto-initializes on first access.
ZenohDartBindings get bindings {
  if (!_initialized) ensureInitialized();
  return _bindings;
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
      // Prefer native/ (original prebuilt) over .dart_tool/lib/ (hook copy).
      // The Dart VM may load .dart_tool/lib/ via CodeAsset metadata with
      // NoActiveIsolateScope — loading from a DIFFERENT path ensures our
      // DynamicLibrary.open() creates a separate dlopen handle that is not
      // tainted by the VM's loading mechanism.
      final nativeFile = File.fromUri(
        packageRoot.resolve('native/linux/x86_64/$libraryName'),
      );
      if (nativeFile.existsSync()) return nativeFile.path;
      final hookFile = File.fromUri(
        packageRoot.resolve('.dart_tool/lib/$libraryName'),
      );
      if (hookFile.existsSync()) return hookFile.path;
    }

    // Fallback: try relative to current working directory
    final candidates = <String>[
      'native/linux/x86_64/$libraryName',
      '.dart_tool/lib/$libraryName',
      'packages/zenoh/native/linux/x86_64/$libraryName',
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

/// Ensures the native library is loaded and the Dart API DL is initialized.
///
/// Loads libzenoh_dart.so via [DynamicLibrary.open] on the main thread,
/// which also transitively loads libzenohc.so via DT_NEEDED (RPATH=$ORIGIN).
/// This avoids the `@Native` loading path that causes inter-process crashes.
///
/// Must be called before any FFI usage. Safe to call multiple times.
void ensureInitialized() {
  if (_initialized) return;

  final libPath = _resolveLibraryPath('libzenoh_dart.so');
  if (libPath == null) {
    throw StateError(
      'Could not find libzenoh_dart.so. Ensure the build hook has run.',
    );
  }

  final lib = DynamicLibrary.open(libPath);
  _bindings = ZenohDartBindings(lib);

  final result = _bindings.zd_init_dart_api_dl(NativeApi.initializeApiDLData);
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }

  _initialized = true;
}
