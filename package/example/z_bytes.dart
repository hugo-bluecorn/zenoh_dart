import 'dart:typed_data';

import 'package:zenoh/zenoh.dart';

void main() {
  // Section 1: Raw bytes and string round-trips
  {
    // Raw bytes
    final inputBytes = Uint8List.fromList([1, 2, 3, 4]);
    final payload = ZBytes.fromUint8List(inputBytes);
    final outputBytes = payload.toBytes();
    final pass = _listEquals(inputBytes, outputBytes);
    print('  ${pass ? "PASS" : "FAIL"}: raw bytes round-trip');
    payload.dispose();
  }
  {
    // String
    const inputStr = 'test';
    final payload = ZBytes.fromString(inputStr);
    final outputStr = payload.toStr();
    final pass = inputStr == outputStr;
    print('  ${pass ? "PASS" : "FAIL"}: string round-trip');
    payload.dispose();
  }

  // Section 2: Single-value serialization round-trips
  {
    // Int
    const inputInt = 1234;
    final payload = ZBytes.fromInt(inputInt);
    final outputInt = payload.toInt();
    final pass = inputInt == outputInt;
    print('  ${pass ? "PASS" : "FAIL"}: int round-trip');
    payload.dispose();
  }
  {
    // Double
    const inputDouble = 3.14;
    final payload = ZBytes.fromDouble(inputDouble);
    final outputDouble = payload.toDouble();
    final pass = inputDouble == outputDouble;
    print('  ${pass ? "PASS" : "FAIL"}: double round-trip');
    payload.dispose();
  }
  {
    // Bool
    const inputBool = true;
    final payload = ZBytes.fromBool(inputBool);
    final outputBool = payload.toBool();
    final pass = inputBool == outputBool;
    print('  ${pass ? "PASS" : "FAIL"}: bool round-trip');
    payload.dispose();
  }

  // Section 3: Serializer/Deserializer with arithmetic types, strings, bytes
  {
    final ser = ZSerializer();
    ser.serializeUint32(42);
    ser.serializeDouble(2.718);
    ser.serializeString('hello');
    ser.serializeBytes(Uint8List.fromList([10, 20, 30]));
    final payload = ser.finish();
    ser.dispose();

    final deser = ZDeserializer(payload);
    final u32 = deser.deserializeUint32();
    final d = deser.deserializeDouble();
    final s = deser.deserializeString();
    final b = deser.deserializeBytes();
    deser.dispose();
    payload.dispose();

    final pass =
        u32 == 42 &&
        d == 2.718 &&
        s == 'hello' &&
        _listEquals(b, Uint8List.fromList([10, 20, 30]));
    print('  ${pass ? "PASS" : "FAIL"}: serializer/deserializer multi-value');
  }

  // Section 4: Composite -- sequence of key-value pairs
  {
    final kvs = [(0, 'abc'), (1, 'def')];

    final ser = ZSerializer();
    ser.serializeSequenceLength(kvs.length);
    for (final (key, value) in kvs) {
      ser.serializeInt32(key);
      ser.serializeString(value);
    }
    final payload = ser.finish();
    ser.dispose();

    final deser = ZDeserializer(payload);
    final numElements = deser.deserializeSequenceLength();
    final outputKvs = <(int, String)>[];
    for (var i = 0; i < numElements; i++) {
      final key = deser.deserializeInt32();
      final value = deser.deserializeString();
      outputKvs.add((key, value));
    }
    deser.dispose();
    payload.dispose();

    var pass = numElements == kvs.length;
    for (var i = 0; i < kvs.length && pass; i++) {
      pass = kvs[i].$1 == outputKvs[i].$1 && kvs[i].$2 == outputKvs[i].$2;
    }
    print('  ${pass ? "PASS" : "FAIL"}: composite key-value sequence');
  }

  // Section 5: ZBytesWriter -- writeAll and append
  {
    final writer = ZBytesWriter();
    writer.writeAll(Uint8List.fromList([0, 1, 2]));
    writer.writeAll(Uint8List.fromList([3, 4]));
    final payload = writer.finish();
    writer.dispose();

    final output = payload.toBytes();
    payload.dispose();

    final expected = Uint8List.fromList([0, 1, 2, 3, 4]);
    final pass = _listEquals(output, expected);
    print('  ${pass ? "PASS" : "FAIL"}: writer writeAll');
  }
  {
    final b1 = ZBytes.fromUint8List(
      Uint8List.fromList([0x61, 0x62, 0x63]),
    ); // "abc"
    final b2 = ZBytes.fromUint8List(
      Uint8List.fromList([0x64, 0x65, 0x66]),
    ); // "def"
    final b3 = ZBytes.fromUint8List(
      Uint8List.fromList([0x68, 0x69, 0x6a]),
    ); // "hij"

    final writer = ZBytesWriter();
    writer.append(b1);
    writer.append(b2);
    writer.append(b3);
    final payload = writer.finish();
    writer.dispose();

    final output = payload.toBytes();
    payload.dispose();

    final expected = Uint8List.fromList([
      0x61,
      0x62,
      0x63,
      0x64,
      0x65,
      0x66,
      0x68,
      0x69,
      0x6a,
    ]);
    final pass = _listEquals(output, expected);
    print('  ${pass ? "PASS" : "FAIL"}: writer append');
  }

  // Section 6: Slice iterator
  {
    final b1 = ZBytes.fromString('abc');
    final b2 = ZBytes.fromString('def');
    final b3 = ZBytes.fromString('hij');

    final writer = ZBytesWriter();
    writer.append(b1);
    writer.append(b2);
    writer.append(b3);
    final payload = writer.finish();
    writer.dispose();

    final slices = payload.slices.toList();
    payload.dispose();

    // Verify we got at least one slice and the total content is correct
    final totalContent = slices.fold<List<int>>([], (acc, s) => acc..addAll(s));
    final expected = [0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x68, 0x69, 0x6a];
    final pass =
        slices.isNotEmpty &&
        _listEquals(
          Uint8List.fromList(totalContent),
          Uint8List.fromList(expected),
        );
    print('  ${pass ? "PASS" : "FAIL"}: slice iterator');
  }
}

/// Compares two [Uint8List] for element-wise equality.
bool _listEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
