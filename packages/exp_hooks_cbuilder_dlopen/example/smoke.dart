import 'dart:io';

import 'package:exp_hooks_cbuilder_dlopen/exp_hooks_cbuilder_dlopen.dart';

void main() {
  try {
    final result = initZenohDart();
    print('initZenohDart() returned: $result');
  } on Object catch (e) {
    stderr.writeln('initZenohDart() failed: $e');
    exit(1);
  }
}
