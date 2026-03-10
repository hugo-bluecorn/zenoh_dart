import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final packageRoot = input.packageRoot;

    // Compile minimal C shim from vendored source using CBuilder.
    // Links against the prebuilt libzenohc.so in native/linux/x86_64/.
    final cbuilder = CBuilder.library(
      name: 'zenoh_dart',
      assetName: 'src/bindings.dart',
      sources: ['src/zenoh_dart_minimal.c', 'src/dart/dart_api_dl.c'],
      includes: [
        'include', // zenoh-c headers
        'src/dart', // dart_api_dl.h
        'src/dart/include', // dart_api.h, dart_native_api.h
      ],
      libraries: ['zenohc'],
      flags: ['-L${packageRoot.resolve('native/linux/x86_64/').toFilePath()}'],
    );

    await cbuilder.run(input: input, output: output);

    // Also declare prebuilt libzenohc.so as a CodeAsset so the runtime
    // can find it alongside the compiled libzenoh_dart.so.
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/zenohc.dart',
        linkMode: DynamicLoadingBundled(),
        file: packageRoot.resolve('native/linux/x86_64/libzenohc.so'),
      ),
    );
  });
}
