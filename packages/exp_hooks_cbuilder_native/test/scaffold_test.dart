import 'dart:convert';
import 'dart:io';

import 'package:exp_hooks_cbuilder_native/exp_hooks_cbuilder_native.dart';
import 'package:test/test.dart';

void main() {
  group('package scaffold', () {
    test('barrel file exports initZenohDart function', () {
      expect(initZenohDart, isA<bool Function()>());
    });

    test('package resolves in workspace', () {
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
            (p as Map<String, dynamic>)['name'] == 'exp_hooks_cbuilder_native',
      );
      expect(
        hasPackage,
        isTrue,
        reason: 'exp_hooks_cbuilder_native should be in package_config.json',
      );
    });

    test('pubspec declares native_toolchain_c dependency', () {
      final workspaceRoot = Directory.current.path.contains('packages/')
          ? Directory.current.path.split('packages/').first
          : Directory.current.path;
      final pubspecFile = File(
        '$workspaceRoot/packages/exp_hooks_cbuilder_native/pubspec.yaml',
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

    test('no DynamicLibrary.open in package source', () {
      final workspaceRoot = Directory.current.path.contains('packages/')
          ? Directory.current.path.split('packages/').first
          : Directory.current.path;
      final libDir = Directory(
        '$workspaceRoot/packages/exp_hooks_cbuilder_native/lib',
      );
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        expect(
          content,
          isNot(contains('DynamicLibrary.open')),
          reason: 'Found DynamicLibrary.open in ${file.path}',
        );
      }
    });
  });
}
