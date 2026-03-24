import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zenoh/zenoh.dart';

void main() {
  group('ZenohId', () {
    test('stores 16 bytes', () {
      final input = Uint8List.fromList([
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
      final zid = ZenohId(input);

      expect(zid.bytes.length, equals(16));
      expect(zid.bytes, equals(input));
    });

    test('toHexString produces hex representation', () {
      final input = Uint8List.fromList([
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      final zid = ZenohId(input);

      final hex = zid.toHexString();
      expect(hex, isNotEmpty);
      expect(zid.toString(), equals(hex));
    });

    test('equality and hashCode', () {
      final bytes1 = Uint8List.fromList([
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
      final bytes2 = Uint8List.fromList([
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
      final bytes3 = Uint8List.fromList([
        16,
        15,
        14,
        13,
        12,
        11,
        10,
        9,
        8,
        7,
        6,
        5,
        4,
        3,
        2,
        1,
      ]);

      final zid1 = ZenohId(bytes1);
      final zid2 = ZenohId(bytes2);
      final zid3 = ZenohId(bytes3);

      expect(zid1, equals(zid2));
      expect(zid1.hashCode, equals(zid2.hashCode));
      expect(zid1, isNot(equals(zid3)));
    });

    test('all-zero bytes produces valid hex string', () {
      final input = Uint8List(16); // all zeros
      final zid = ZenohId(input);

      final hex = zid.toHexString();
      expect(hex, isNotEmpty);
      // Should be all zeros in hex
      expect(hex, matches(RegExp(r'^[0]+$')));
    });
  });

  group('WhatAmI', () {
    test('fromInt maps correct values', () {
      expect(WhatAmI.fromInt(1), equals(WhatAmI.router));
      expect(WhatAmI.fromInt(2), equals(WhatAmI.peer));
      expect(WhatAmI.fromInt(4), equals(WhatAmI.client));
    });

    test('fromInt throws on invalid value', () {
      expect(() => WhatAmI.fromInt(0), throwsArgumentError);
      expect(() => WhatAmI.fromInt(3), throwsArgumentError);
      expect(() => WhatAmI.fromInt(5), throwsArgumentError);
      expect(() => WhatAmI.fromInt(-1), throwsArgumentError);
    });
  });
}
