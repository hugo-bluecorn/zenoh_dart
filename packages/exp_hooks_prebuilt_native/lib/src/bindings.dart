@DefaultAsset('package:exp_hooks_prebuilt_native/src/bindings.dart')
library;

import 'dart:ffi';
import 'package:ffi/ffi.dart';

@Native<IntPtr Function(Pointer<Void>)>(symbol: 'zd_init_dart_api_dl')
external int zdInitDartApiDl(Pointer<Void> data);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'zd_init_log')
external void zdInitLog(Pointer<Utf8> filter);
