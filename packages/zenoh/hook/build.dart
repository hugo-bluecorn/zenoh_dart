import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    final nativeDir = _nativeDir(input.packageRoot, codeConfig);

    // Primary: C shim (bundled for distribution; loaded at runtime via DynamicLibrary.open())
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenoh_dart.so'),
      ),
    );

    // Secondary: zenoh-c runtime (resolved by OS linker via DT_NEEDED)
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenohc.so'),
      ),
    );
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
