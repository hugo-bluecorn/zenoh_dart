## 0.0.1

Initial release — Phases 0-5 complete.

- **62 C shim functions** wrapping zenoh-c v1.7.2
- **18 Dart API classes**: Zenoh, Config, Session, KeyExpr, ZBytes, Publisher, Subscriber, Sample, SampleKind, Encoding, CongestionControl, Priority, ShmProvider, ShmMutBuffer, ZenohId, WhatAmI, Hello, ZenohException
- **7 CLI examples**: z_put, z_delete, z_sub, z_pub, z_pub_shm, z_info, z_scout
- **193 integration tests** including inter-process TCP validation
- Shared memory zero-copy publishing (Linux)
- Network scouting and session info
- Build hooks for native library distribution (Linux x86_64, Android arm64-v8a/x86_64)
- DynamicLibrary.open() loading (avoids @Native inter-process crashes)
