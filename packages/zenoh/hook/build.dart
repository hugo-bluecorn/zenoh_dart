import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final nativeDir = input.packageRoot.resolve('native/linux/x86_64/');

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
