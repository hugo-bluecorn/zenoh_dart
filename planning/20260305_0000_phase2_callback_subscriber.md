# Phase 2: Callback Subscriber

**Created:** 2026-03-05
**Phase:** Phase 2
**Status:** planned

## Overview

Implement a callback-based subscriber for zenoh, enabling Dart consumers to receive `Sample` data via a `Stream<Sample>`. This is the first phase using the NativePort callback bridge pattern -- zenoh-c calls a C callback on its internal threads, the C shim serializes the sample into a `Dart_CObject` array, posts it to a `Dart_Port`, and a `ReceivePort` on the Dart side deserializes it into `Sample` objects fed through a `StreamController`.

## Slice Decomposition

| Slice | Name | Tests | Depends | Blocks |
|-------|------|-------|---------|--------|
| 1 | Sample/SampleKind + C shim + ffigen + lifecycle | 7 | none | 2,3,4,5 |
| 2 | NativePort bridge -- PUT samples via stream | 4 | 1 | 3,4,5 |
| 3 | DELETE sample kind + stream close | 4 | 2 | 4,5 |
| 4 | Multiple subscribers + independence | 3 | 3 | 5 |
| 5 | z_sub CLI example | 4 | 3,4 | -- |
| **Total** | | **20** | | |

## Key Architectural Decisions

1. **NativePort bridge pattern:** C shim stores `Dart_Port` in closure context. Zenoh callback posts `Dart_CObject` array via `Dart_PostCObject_DL` (only thread-safe Dart FFI function). ReceivePort deserializes on main isolate event loop.
2. **Context struct:** Heap-allocated struct holding `Dart_Port`, freed in closure `_drop` callback.
3. **Payload decoding:** C shim posts payload as Uint8List. Dart decodes via `utf8.decode()`.
4. **Non-broadcast StreamController:** One logical consumer per subscriber.
5. **NULL subscriber options:** `allowed_origin` deferred to future phase.

## New API Surface

- `Sample` class (keyExpr, payload, kind, attachment)
- `SampleKind` enum (put, delete)
- `Subscriber` class (stream, close)
- `Session.declareSubscriber(String keyExpr)` method

## C Shim Functions

- `zd_subscriber_sizeof()` -- returns sizeof(z_owned_subscriber_t)
- `zd_declare_subscriber(session, subscriber, keyexpr, dart_port)` -- declares subscriber with NativePort callback
- `zd_subscriber_drop(subscriber)` -- undeclares and drops subscriber

## Files Modified/Created

- `src/zenoh_dart.{h,c}` -- C shim additions
- `packages/zenoh/lib/src/sample.dart` -- new
- `packages/zenoh/lib/src/subscriber.dart` -- new
- `packages/zenoh/lib/src/session.dart` -- modified (declareSubscriber)
- `packages/zenoh/lib/zenoh.dart` -- modified (exports)
- `packages/zenoh/ffigen.yaml` -- modified (opaque types)
- `packages/zenoh/bin/z_sub.dart` -- new CLI example
- `packages/zenoh/test/subscriber_test.dart` -- new (16 tests)
- `packages/zenoh/test/z_sub_cli_test.dart` -- new (4 tests)

## Reference Material

- Phase spec: `docs/phases/phase-02-sub.md`
- zenoh-cpp pub/sub test: `extern/zenoh-cpp/tests/universal/network/pub_sub.cxx`
- zenoh-c integration test: `extern/zenoh-c/tests/z_int_pub_sub_test.c`
- zenoh-c example: `extern/zenoh-c/examples/z_sub.c`
