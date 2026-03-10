import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageName = input.packageName;
    final nativeDir = input.packageRoot.resolve('native/linux/x86_64/');

    // Primary asset: libzenoh_dart.so
    // Name MUST match @DefaultAsset URI in bindings.dart.
    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenoh_dart.so'),
      ),
    );

    // Secondary asset: libzenohc.so (dependency of libzenoh_dart.so)
    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: 'src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: nativeDir.resolve('libzenohc.so'),
      ),
    );
  });
}
