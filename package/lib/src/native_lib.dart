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

/// Resolves the absolute path to a prebuilt native library.
///
/// Prefers the `native/linux/x86_64/` directory (original prebuilts) over
/// `.dart_tool/lib/` (build hook copy). This is critical: the Dart VM loads
/// CodeAsset libraries from `.dart_tool/lib/` via `NoActiveIsolateScope`,
/// which taints the dlopen handle. Loading from a separate path ensures
/// [DynamicLibrary.open] creates an independent, untainted handle.
String? _resolveLibraryPath(String libraryName) {
  // Try package URI resolution first (works in pure Dart,
  // but throws UnsupportedError in Flutter test runner).
  try {
    final packageUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:zenoh/src/native_lib.dart'),
    );
    if (packageUri != null) {
      final packageRoot = packageUri.resolve('../../');
      final nativeFile = File.fromUri(
        packageRoot.resolve(
          'native/linux/x86_64/$libraryName',
        ),
      );
      if (nativeFile.existsSync()) return nativeFile.path;
      final hookFile = File.fromUri(
        packageRoot.resolve('.dart_tool/lib/$libraryName'),
      );
      if (hookFile.existsSync()) return hookFile.path;
    }
  } catch (_) {
    // Isolate.resolvePackageUriSync is unsupported in
    // Flutter's test runner — fall through to CWD probing.
  }

  // Fallback: try relative to current working directory.
  final candidates = <String>[
    'native/linux/x86_64/$libraryName',
    '.dart_tool/lib/$libraryName',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }

  return null;
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

  DynamicLibrary lib;
  if (Platform.isAndroid) {
    // Android: APK linker resolves from lib/<abi>/ automatically.
    // libzenohc.so loads transitively via DT_NEEDED.
    lib = DynamicLibrary.open('libzenoh_dart.so');
  } else {
    final libPath = _resolveLibraryPath('libzenoh_dart.so');
    if (libPath != null) {
      lib = DynamicLibrary.open(libPath);
    } else {
      // Last resort: let the OS linker resolve via RUNPATH/LD_LIBRARY_PATH.
      // This handles Flutter desktop (RUNPATH=$ORIGIN/lib in the runner binary).
      try {
        lib = DynamicLibrary.open('libzenoh_dart.so');
      } catch (e) {
        throw StateError(
          'Could not find libzenoh_dart.so. Ensure the build hook has run.',
        );
      }
    }
  }

  _bindings = ZenohDartBindings(lib);

  final result = _bindings.zd_init_dart_api_dl(NativeApi.initializeApiDLData);
  if (result != 0) {
    throw StateError('Failed to initialize Dart API DL (code: $result)');
  }

  _initialized = true;
}
