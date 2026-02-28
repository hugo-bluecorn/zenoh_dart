# Phase 16: z_bytes (Serialization/Deserialization)

## Project Context

`zenoh` is a pure Dart FFI package providing bindings for zenoh-c v1.7.2 via a
C shim layer. See `docs/phases/phase-00-bootstrap.md` for full architecture.

## Prior Phases

### Phase 0 (Bootstrap) — completed
- Basic `ZBytes` class with `fromString()`, `fromUint8List()`, `toStr()`

### Phase 4 (Core SHM) — completed
- SHM-backed bytes, `ZBytes.isShmBacked`, `ZBytes.clone()`

### Phase 12 (Ping/Pong) — completed
- `ZBytes.toBytes()` (raw Uint8List)

## This Phase's Goal

Implement the full bytes serialization/deserialization API. This is a standalone
phase (no network) that exercises zenoh-c's `ze_serialize_*` / `ze_deserialize_*`
functions and the `z_bytes_writer_*` / `z_bytes_reader_*` APIs.

**Reference example**: `extern/zenoh-c/examples/z_bytes.c`

### Serialization approaches in zenoh-c

1. **Simple conversion**: `z_bytes_from_*` / `z_bytes_to_*` (strings, buffers)
2. **Typed serialization**: `ze_serialize_*` / `ze_deserialize_*` (int, float, string, bool)
3. **Streaming writer**: `z_bytes_writer_*` for building multi-part payloads
4. **Streaming reader**: `z_bytes_reader_*` for reading fragmented data
5. **Composite serialization**: `ze_serializer_*` / `ze_deserializer_*` for sequences and key-value pairs

## C Shim Functions to Add

### Typed serialization

```c
// Serialize primitive types
FFI_PLUGIN_EXPORT int zd_serialize_uint8(z_owned_bytes_t* out, uint8_t val);
FFI_PLUGIN_EXPORT int zd_serialize_uint16(z_owned_bytes_t* out, uint16_t val);
FFI_PLUGIN_EXPORT int zd_serialize_uint32(z_owned_bytes_t* out, uint32_t val);
FFI_PLUGIN_EXPORT int zd_serialize_uint64(z_owned_bytes_t* out, uint64_t val);
FFI_PLUGIN_EXPORT int zd_serialize_int8(z_owned_bytes_t* out, int8_t val);
FFI_PLUGIN_EXPORT int zd_serialize_int16(z_owned_bytes_t* out, int16_t val);
FFI_PLUGIN_EXPORT int zd_serialize_int32(z_owned_bytes_t* out, int32_t val);
FFI_PLUGIN_EXPORT int zd_serialize_int64(z_owned_bytes_t* out, int64_t val);
FFI_PLUGIN_EXPORT int zd_serialize_float(z_owned_bytes_t* out, float val);
FFI_PLUGIN_EXPORT int zd_serialize_double(z_owned_bytes_t* out, double val);
FFI_PLUGIN_EXPORT int zd_serialize_bool(z_owned_bytes_t* out, bool val);
FFI_PLUGIN_EXPORT int zd_serialize_string(z_owned_bytes_t* out, const char* val);
FFI_PLUGIN_EXPORT int zd_serialize_buf(z_owned_bytes_t* out, const uint8_t* data, size_t len);

// Deserialize primitive types
FFI_PLUGIN_EXPORT int zd_deserialize_uint8(const z_loaned_bytes_t* bytes, uint8_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_uint16(const z_loaned_bytes_t* bytes, uint16_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_uint32(const z_loaned_bytes_t* bytes, uint32_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_uint64(const z_loaned_bytes_t* bytes, uint64_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_int8(const z_loaned_bytes_t* bytes, int8_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_int16(const z_loaned_bytes_t* bytes, int16_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_int32(const z_loaned_bytes_t* bytes, int32_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_int64(const z_loaned_bytes_t* bytes, int64_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_float(const z_loaned_bytes_t* bytes, float* out);
FFI_PLUGIN_EXPORT int zd_deserialize_double(const z_loaned_bytes_t* bytes, double* out);
FFI_PLUGIN_EXPORT int zd_deserialize_bool(const z_loaned_bytes_t* bytes, bool* out);
FFI_PLUGIN_EXPORT int zd_deserialize_string(const z_loaned_bytes_t* bytes, z_owned_string_t* out);
FFI_PLUGIN_EXPORT int zd_deserialize_slice(const z_loaned_bytes_t* bytes, z_owned_slice_t* out);
```

### Composite serializer/deserializer

```c
// Create an empty serializer
FFI_PLUGIN_EXPORT void zd_serializer_empty(ze_owned_serializer_t* ser);

// Serialize into serializer
FFI_PLUGIN_EXPORT int zd_serializer_serialize_uint32(ze_loaned_serializer_t* ser, uint32_t val);
FFI_PLUGIN_EXPORT int zd_serializer_serialize_string(ze_loaned_serializer_t* ser, const char* val);
FFI_PLUGIN_EXPORT int zd_serializer_serialize_sequence_length(ze_loaned_serializer_t* ser, size_t len);
FFI_PLUGIN_EXPORT int zd_serializer_serialize_buf(ze_loaned_serializer_t* ser, const uint8_t* data, size_t len);

// Finish serializer → bytes
FFI_PLUGIN_EXPORT void zd_serializer_finish(ze_owned_serializer_t* ser, z_owned_bytes_t* out);

// Loan serializer
FFI_PLUGIN_EXPORT ze_loaned_serializer_t* zd_serializer_loan_mut(ze_owned_serializer_t* ser);

// Create deserializer from bytes
FFI_PLUGIN_EXPORT void zd_deserializer_from_bytes(ze_deserializer_t* deser, const z_loaned_bytes_t* bytes);

// Deserialize from deserializer
FFI_PLUGIN_EXPORT int zd_deserializer_deserialize_uint32(ze_deserializer_t* deser, uint32_t* out);
FFI_PLUGIN_EXPORT int zd_deserializer_deserialize_string(ze_deserializer_t* deser, z_owned_string_t* out);
FFI_PLUGIN_EXPORT int zd_deserializer_deserialize_sequence_length(ze_deserializer_t* deser, size_t* out);
FFI_PLUGIN_EXPORT int zd_deserializer_deserialize_slice(ze_deserializer_t* deser, z_owned_slice_t* out);
```

### Bytes writer/reader

```c
// Create empty writer
FFI_PLUGIN_EXPORT void zd_bytes_writer_empty(z_owned_bytes_writer_t* writer);
FFI_PLUGIN_EXPORT z_loaned_bytes_writer_t* zd_bytes_writer_loan_mut(z_owned_bytes_writer_t* writer);
FFI_PLUGIN_EXPORT int zd_bytes_writer_write_all(z_loaned_bytes_writer_t* writer, const uint8_t* data, size_t len);
FFI_PLUGIN_EXPORT int zd_bytes_writer_append(z_loaned_bytes_writer_t* writer, z_owned_bytes_t* bytes);
FFI_PLUGIN_EXPORT void zd_bytes_writer_finish(z_owned_bytes_writer_t* writer, z_owned_bytes_t* out);

// Slice iterator for fragmented reading
FFI_PLUGIN_EXPORT void zd_bytes_get_slice_iterator(const z_loaned_bytes_t* bytes, z_bytes_slice_iterator_t* iter);
FFI_PLUGIN_EXPORT bool zd_bytes_slice_iterator_next(z_bytes_slice_iterator_t* iter, z_view_slice_t* out);
```

## zenoh-c APIs Wrapped

All `ze_serialize_*`, `ze_deserialize_*`, `ze_serializer_*`, `ze_deserializer_*`,
`z_bytes_writer_*`, `z_bytes_get_slice_iterator`, `z_bytes_slice_iterator_next`.

## Dart API Surface

### New file: `packages/zenoh/lib/src/serializer.dart`

```dart
/// Serializes data into zenoh bytes format.
class ZSerializer {
  ZSerializer();

  void serializeUint32(int value);
  void serializeInt64(int value);
  void serializeDouble(double value);
  void serializeBool(bool value);
  void serializeString(String value);
  void serializeBytes(Uint8List value);
  void serializeSequenceLength(int length);

  /// Finish serialization and produce bytes.
  ZBytes finish();
}
```

### New file: `packages/zenoh/lib/src/deserializer.dart`

```dart
/// Deserializes data from zenoh bytes format.
class ZDeserializer {
  ZDeserializer(ZBytes bytes);

  int deserializeUint32();
  int deserializeInt64();
  double deserializeDouble();
  bool deserializeBool();
  String deserializeString();
  Uint8List deserializeBytes();
  int deserializeSequenceLength();
}
```

### Modify `packages/zenoh/lib/src/bytes.dart`

Add static serialization convenience methods:

```dart
class ZBytes {
  /// Serialize a single value.
  static ZBytes fromInt(int value);
  static ZBytes fromDouble(double value);
  static ZBytes fromBool(bool value);

  /// Deserialize a single value.
  int toInt();
  double toDouble();
  bool toBool();

  /// Iterate over slices (for fragmented data).
  Iterable<Uint8List> get slices;
}
```

## CLI Example to Create

### `packages/zenoh/bin/z_bytes.dart`

Mirrors `extern/zenoh-c/examples/z_bytes.c`:

```
Usage: fvm dart run -C packages/zenoh bin/z_bytes.dart
```

Behavior (no network, pure serialization test):
1. Simple: string → bytes → string, assert equality
2. Simple: Uint8List → bytes → Uint8List, assert equality
3. Typed: serialize uint32, float, string → deserialize, assert
4. Composite: serialize sequence of (uint32, string) pairs → deserialize, assert
5. Writer: write multiple chunks → finish → read back via slice iterator
6. Print all results as pass/fail

## Verification

1. `fvm dart analyze packages/zenoh` — no errors
2. **Unit test**: Roundtrip string serialization/deserialization
3. **Unit test**: Roundtrip int/float/bool serialization
4. **Unit test**: Composite serializer with sequence of key-value pairs
5. **Unit test**: Bytes writer produces correct multi-chunk payload
6. **Unit test**: Slice iterator reads all chunks correctly
7. Run `bin/z_bytes.dart` — all assertions pass
