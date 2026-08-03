import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// The bundled libraries, mapped to the asset name each is registered under.
///
/// libzenoh_dart.so is the C shim (loaded at runtime via
/// DynamicLibrary.open()); libzenohc.so is the zenoh-c runtime, resolved by
/// the OS linker via DT_NEEDED.
const _bundledLibraries = <String, String>{
  'libzenoh_dart.so': 'src/bindings.dart',
  'libzenohc.so': 'src/zenohc.dart',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final nativeDir = _nativeDir(input.packageRoot, codeConfig);

    // Both libraries must land in the SAME directory: libzenoh_dart.so carries
    // RUNPATH=$ORIGIN and resolves libzenohc.so via DT_NEEDED from its own
    // directory, so staging only the shim aborts the load.
    for (final MapEntry(key: fileName, value: assetName)
        in _bundledLibraries.entries) {
      final source = nativeDir.resolve(fileName);
      final staged = input.outputDirectory.resolve(fileName);

      // Register the copy, never the source. For a consumer resolving this
      // package from pub.dev, packageRoot IS the pub cache — a directory a
      // build hook must not write to, and whose registered files the build
      // system will garbage-collect as its own stale outputs, corrupting the
      // cached package for every project on the machine.
      File.fromUri(source).copySync(staged.toFilePath());

      // Re-run this hook when a refreshed prebuilt replaces the source, so the
      // staged copy does not go stale.
      output.dependencies.add(source);

      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: assetName,
          linkMode: DynamicLoadingBundled(),
          file: staged,
        ),
      );
    }
  });
}

Uri _nativeDir(Uri packageRoot, CodeConfig config) {
  final os = config.targetOS;
  final arch = config.targetArchitecture;

  if (os == OS.android) {
    final abi = _androidAbi(arch);
    return packageRoot.resolve('native/android/$abi/');
  }
  if (os == OS.linux) {
    // x64 → x86_64 to match uname convention
    final dirName = arch == Architecture.x64 ? 'x86_64' : arch.toString();
    return packageRoot.resolve('native/linux/$dirName/');
  }
  throw UnsupportedError('Unsupported target OS: $os');
}

String _androidAbi(Architecture arch) => switch (arch) {
  Architecture.arm64 => 'arm64-v8a',
  Architecture.arm => 'armeabi-v7a',
  Architecture.x64 => 'x86_64',
  Architecture.ia32 => 'x86',
  _ => throw UnsupportedError('Unsupported Android architecture: $arch'),
};
