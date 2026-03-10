import 'dart:convert';
import 'dart:io';

import 'package:exp_hooks_cbuilder_dlopen/exp_hooks_cbuilder_dlopen.dart';
import 'package:test/test.dart';

void main() {
  group('package scaffold', () {
    test('barrel file exports initZenohDart function', () {
      // Verify the function exists and is callable
      expect(initZenohDart, isA<bool Function()>());
    });

    test('package resolves in workspace', () {
      // The workspace root package_config.json must contain our package.
      final workspaceRoot = Directory.current.path.contains('packages/')
          ? Directory.current.path.split('packages/').first
          : Directory.current.path;
      final packageConfigFile = File(
        '$workspaceRoot/.dart_tool/package_config.json',
      );
      final configFile = packageConfigFile.existsSync()
          ? packageConfigFile
          : File(
              '${Platform.environment['MONOREPO_ROOT'] ?? workspaceRoot}'
              '/.dart_tool/package_config.json',
            );
      expect(
        configFile.existsSync(),
        isTrue,
        reason: 'Workspace package_config.json should exist',
      );

      final content =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final packages = content['packages'] as List<dynamic>;
      final hasPackage = packages.any(
        (p) =>
            (p as Map<String, dynamic>)['name'] ==
            'exp_hooks_cbuilder_dlopen',
      );
      expect(
        hasPackage,
        isTrue,
        reason: 'exp_hooks_cbuilder_dlopen should be in package_config.json',
      );
    });

    test('pubspec declares native_toolchain_c dependency', () {
      // Find the package's pubspec.yaml
      final workspaceRoot = Directory.current.path.contains('packages/')
          ? Directory.current.path.split('packages/').first
          : Directory.current.path;
      final pubspecFile = File(
        '$workspaceRoot/packages/exp_hooks_cbuilder_dlopen/pubspec.yaml',
      );
      expect(
        pubspecFile.existsSync(),
        isTrue,
        reason: 'pubspec.yaml should exist',
      );

      final content = pubspecFile.readAsStringSync();
      expect(
        content.contains('native_toolchain_c:'),
        isTrue,
        reason: 'pubspec.yaml should declare native_toolchain_c dependency',
      );
    });
  });
}
