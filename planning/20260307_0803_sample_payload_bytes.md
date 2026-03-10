# Feature Notes: Sample.payloadBytes

**Created:** 2026-03-07
**Status:** Planning

> This document is a read-only planning archive produced by the tdd-planner
> agent. It captures architectural context, design decisions, and trade-offs
> for the feature. Live implementation status is tracked in `.tdd-progress.md`.

---

## Overview

### Purpose
Add a `payloadBytes: Uint8List` field to the `Sample` class, exposing raw payload bytes already available in the subscriber NativePort callback. Enables binary data consumers (Protobuf, CBOR, images) without breaking the existing `payload` String API.

### Use Cases
- Binary protocol support (Protobuf, CBOR, MessagePack)
- Image/media payload handling
- Counter app MVP (needs raw bytes for numeric payloads)
- Any consumer that doesn't want UTF-8 decoding overhead

### Context
The C shim subscriber callback already posts payload as `Uint8List` (at `message[1]` in the Dart_CObject array). Currently, `subscriber.dart` does `utf8.decode(payloadBytes)` and discards the raw bytes. This ~10-line change retains them.

---

## Architecture

No C shim changes needed. The data flow is:

```
C shim callback → Dart_PostCObject [keyexpr, payload(Uint8List), kind, attachment, encoding]
                                          ↓
subscriber.dart → utf8.decode(payload) → Sample(payload: string)  [CURRENT]
subscriber.dart → Sample(payload: string, payloadBytes: rawBytes)  [NEW]
```

---

## Key Design Decisions

1. **`payloadBytes` is required, not optional.** Every sample has a payload (even deletes have zero-length). Required avoids null checks.

2. **No C shim changes.** Bytes already flow through. Pure Dart change.

3. **`const` constructor may be lost.** `Uint8List` is not a compile-time constant. Acceptable -- Sample is only constructed at runtime.

4. **Potential refactor: lazy `payload` getter.** Could eliminate data duplication by computing `payload` from `payloadBytes` on demand. Implementation-time decision.

---

## Slice Summary

| Slice | Name | Tests | Depends on | Blocks |
|-------|------|-------|-----------|--------|
| 1 | Sample class payloadBytes field | 3 | none | 2 |
| 2 | Subscriber populates payloadBytes + E2E | 4 | 1 | none |
| **Total** | | **7** | | |
