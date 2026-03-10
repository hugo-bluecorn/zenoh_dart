import 'package:exp_hooks_prebuilt_native/exp_hooks_prebuilt_native.dart';

void main() {
  try {
    final result = initZenohDart();
    print('initZenohDart() returned: $result');
  } catch (e) {
    print('initZenohDart() failed: $e');
    // ignore: avoid_catches_without_on_clauses
  }
}
