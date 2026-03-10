# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pure Dart FFI package providing bindings for [Zenoh](https://zenoh.io/) (a pub/sub/query protocol) via a C shim layer wrapping zenoh-c v1.7.2. This is a Melos monorepo with the main package at `packages/zenoh/`.

## Monorepo Structure

```
zenoh-dart/                     # git repo root
  pubspec.yaml                  # Dart workspace + Melos config
  packages/
    zenoh/                      # pure Dart FFI package
      hook/                     # build hook for @Native code asset registration
      native/                   # prebuilt native libraries (linux/x86_64/)
  src/                          # C shim source (monorepo level)
    zenoh_dart.{h,c}
    CMakeLists.txt
  extern/                       # git submodules
    zenoh-c/ (v1.7.2)
    zenoh-cpp/ (v1.7.2)
    zenoh-kotlin/ zenoh-demos/ cargo-ndk/
  docs/phases/                  # phase specs (source of truth)
  scripts/                      # build scripts
```

## Current Status

**Phase 0 Bootstrap: COMPLETE** — 29 C shim functions, 5 Dart API classes, 33 integration tests.
**Phase P1 Packaging: COMPLETE** — Build infrastructure done in Phase 0. Tier-2 prebuilt placement (`native/linux/x86_64/libzenohc.so`) intentionally deferred — it's a 30-second `mkdir + cp` whenever needed (CI setup, new contributor onboarding, pub.dev prep). The CMake 3-tier discovery, single-load `native_lib.dart`, Android build script, and RPATH configuration are all in place.
**Phase 1 Put/Delete: COMPLETE** — 31 C shim functions, 56 integration tests. `Session.put`, `Session.putBytes`, and `Session.deleteResource` implemented with CLI examples `z_put.dart` and `z_delete.dart`.
**Phase 2 Subscriber: COMPLETE** — 34 C shim functions, 80 integration tests. `Session.declareSubscriber`, `Subscriber`, `Sample`, `SampleKind` implemented via NativePort callback bridge with CLI example `z_sub.dart`.
**Phase 3 Publisher: COMPLETE** — 43 C shim functions, 120 integration tests. `Publisher` with `put`/`putBytes`/`deleteResource`/`keyExpr`/`hasMatchingSubscribers`/`matchingStatus`/`close`; `Encoding`, `CongestionControl`, `Priority` types; `Sample.encoding` field; CLI example `z_pub.dart`.
**Phase 4 SHM Provider: COMPLETE** — 56 C shim functions, 148 integration tests. `ShmProvider`, `ShmMutBuffer` with zero-copy alloc/write/publish; SHM-published data received transparently by standard subscribers; CLI example `z_pub_shm.dart`.
**Phase 5 Scout/Info: COMPLETE** — 62 C shim functions, 185 integration tests. `ZenohId`, `WhatAmI`, `Hello` classes; `Session.zid`/`routersZid()`/`peersZid()`; `Zenoh.scout()`; CLI examples `z_info.dart` and `z_scout.dart`. `Sample.payloadBytes` (`Uint8List`) added as patch 0.6.1.

Available Dart API classes:
- `Zenoh` — Static utilities: `initLog(fallback)` for runtime logger initialization (call before `Session.open()`); `scout(config)` discovers zenoh entities on the network
- `Config` — Session configuration with JSON5 insertion
- `Session` — Open/close zenoh sessions (peer mode); `put(keyExpr, value)`, `putBytes(keyExpr, payload)`, `deleteResource(keyExpr)` one-shot operations; `declareSubscriber(keyExpr)` returns a `Subscriber`; `declarePublisher(keyExpr)` returns a `Publisher`; `zid` returns own `ZenohId`; `routersZid()` and `peersZid()` return connected router/peer IDs
- `KeyExpr` — Key expression creation and validation
- `ZBytes` — Binary payload container with string round-trip; `markConsumed()` for FFI ownership semantics
- `Publisher` — Declared publisher with `put()`, `putBytes()`, `deleteResource()`, `keyExpr`, `hasMatchingSubscribers()`, `matchingStatus` stream, and `close()`
- `Subscriber` — Callback-based subscriber delivering samples via `Stream<Sample>`; `close()` undeclares and frees the native subscriber
- `Sample` — Received data with `keyExpr`, `payload` (UTF-8 string), `payloadBytes` (`Uint8List` raw bytes), `kind` (`SampleKind`), optional `attachment`, and optional `encoding` fields
- `SampleKind` — Enum with `put` and `delete` values
- `Encoding` — MIME type wrapper with 10 predefined constants (`textPlain`, `applicationJson`, etc.) and custom constructor
- `CongestionControl` — Enum with `block` and `drop` congestion control strategies
- `Priority` — Enum with 7 priority levels from `realTime` to `background`
- `ShmProvider` — POSIX shared memory provider with `alloc()`, `allocGcDefragBlocking()`, `available`, and `close()`
- `ShmMutBuffer` — Mutable SHM buffer with `data` pointer (zero-copy write), `length`, `toBytes()` (zero-copy conversion to `ZBytes`), and `dispose()`
- `ZenohId` — 16-byte session/entity identifier with `toHexString()`, equality, and hashCode
- `WhatAmI` — Enum with `router`, `peer`, and `client` values mapping zenoh-c bitmask (1, 2, 4)
- `Hello` — Scouting result with `zid` (`ZenohId`), `whatami` (`WhatAmI`), and `locators` (list of strings) fields
- `ZenohException` — Error type for zenoh operations

Phases 6–18 (query/liveliness/throughput/storage/advanced) are specified in `docs/phases/` but not yet implemented.

## FVM Requirement

**Dart and Flutter are NOT on PATH.** ALL commands must use `fvm`:

```bash
fvm dart ...
fvm flutter ...
fvm dart run melos ...
```

## Build & Development Commands

### zenoh-c native library (prerequisite)

The `extern/zenoh-c` submodule (v1.7.2) provides the native C API. **Developers** modifying the C shim or upgrading zenoh-c need to build it locally. Requires: clang, cmake, ninja, rustc/cargo (stable, MSRV 1.75.0).

```bash
# Configure (one-time, or after CMake changes)
cmake \
  -S extern/zenoh-c \
  -B extern/zenoh-c/build \
  -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=TRUE \
  -DZENOHC_BUILD_IN_SOURCE_TREE=TRUE

# Build (RUSTUP_TOOLCHAIN=stable works around rust-toolchain.toml pinning unreleased channel)
RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release
```

**Build artifacts:**
- Shared library: `extern/zenoh-c/target/release/libzenohc.so`
- Headers: `extern/zenoh-c/include/` (zenoh.h, zenoh_commons.h, zenoh_macros.h)

See `docs/build/01-build-zenoh-c.md` for the full build plan and rationale.

### CMake zenohc discovery

`src/CMakeLists.txt` finds `libzenohc.so` via three-tier discovery:
1. **Android**: `android/src/main/jniLibs/${ANDROID_ABI}/libzenohc.so`
2. **Linux prebuilt**: `native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so`
3. **Developer fallback**: `extern/zenoh-c/target/release/libzenohc.so`

RPATH is set to `$ORIGIN` on Linux for self-contained deployment.

**C shim build:** Running `cmake --build build` from the repo root produces `build/libzenoh_dart.so`. After building, copy both shared libraries to the prebuilt location for build hooks:
```bash
mkdir -p packages/zenoh/native/linux/x86_64/
cp build/libzenoh_dart.so packages/zenoh/native/linux/x86_64/
cp extern/zenoh-c/target/release/libzenohc.so packages/zenoh/native/linux/x86_64/
patchelf --set-rpath '$ORIGIN' packages/zenoh/native/linux/x86_64/libzenoh_dart.so
```

### Android cross-compilation

```bash
# Build libzenohc.so for Android ABIs (requires Rust, NDK, cargo-ndk)
./scripts/build_zenoh_android.sh                  # arm64-v8a + x86_64
./scripts/build_zenoh_android.sh --abi arm64-v8a  # single ABI
```

### Dart package commands

```bash
# Regenerate FFI bindings after modifying src/zenoh_dart.h
cd packages/zenoh && fvm dart run ffigen --config ffigen.yaml

# Analyze Dart code
fvm dart analyze packages/zenoh

# Run all tests (build hooks resolve native libs automatically)
cd packages/zenoh && fvm dart test

# Run a single test file
cd packages/zenoh && fvm dart test test/session_test.dart

# Run a single test by name
cd packages/zenoh && fvm dart test --name "opens session"

# Melos bootstrap (from monorepo root)
fvm dart run melos bootstrap
```

### CLI examples

CLI examples live in `packages/zenoh/example/`. Build hooks resolve native libraries automatically — no `LD_LIBRARY_PATH` needed.

```bash
# Put data on a key expression
cd packages/zenoh && fvm dart run example/z_put.dart -k demo/example/test -p 'Hello from Dart!'

# Delete a key expression
cd packages/zenoh && fvm dart run example/z_delete.dart -k demo/example/test

# Subscribe to a key expression (runs until Ctrl-C)
cd packages/zenoh && fvm dart run example/z_sub.dart -k 'demo/example/**'

# Publish in a loop on a key expression (runs until Ctrl-C)
cd packages/zenoh && fvm dart run example/z_pub.dart -k demo/example/test -p 'Hello from Dart!'

# Publish via shared memory in a loop on a key expression (runs until Ctrl-C)
cd packages/zenoh && fvm dart run example/z_pub_shm.dart -k demo/example/test -p 'Hello from SHM!'

# Print own session ZID and connected router/peer ZIDs
cd packages/zenoh && fvm dart run example/z_info.dart

# Discover zenoh entities on the network (scouts for routers, peers, and clients)
cd packages/zenoh && fvm dart run example/z_scout.dart
```

CLI flags must mirror zenoh-c's examples (`extern/zenoh-c/examples/z_*.c`). When adding a new CLI example in any phase:
1. Match the zenoh-c flag names and short forms exactly (e.g., `-k`/`--key`, `-p`/`--payload`)
2. Document the full usage in the README.md CLI Examples section
3. The `/tdd-finalize-docs` agent must include CLI usage in the README update

## Architecture

### FFI Package Structure

Native C code in `src/` is compiled into a shared library and loaded at runtime via `dart:ffi`.

**Data flow:** Dart API (`packages/zenoh/lib/zenoh.dart`) → Generated bindings (`packages/zenoh/lib/src/bindings.dart`) → Native C (`src/zenoh_dart.{h,c}`) → `libzenohc.so` (resolved by OS linker via DT_NEEDED)

### Key Conventions

- **Short-lived native functions**: Call directly from any isolate (e.g., `zd_put()`)
- **Long-lived native functions**: Must run on a helper isolate to avoid blocking. Uses `SendPort`/`ReceivePort` request-response pattern with `Completer`-based futures.
- **`zd_` prefix**: All C shim symbols (functions, structs, enums, typedefs) must use the `zd_` prefix to avoid collisions with zenoh-c's `z_`/`zc_` namespace. The ffigen.yaml filters on `zd_.*` — symbols without this prefix won't appear in bindings.dart.
- **Binding generation**: `packages/zenoh/lib/src/bindings.dart` is auto-generated with `@Native` annotations — never edit manually. Regenerate with `fvm dart run ffigen --config ffigen.yaml` after changing `src/zenoh_dart.h`. The analyzer excludes this file (`analysis_options.yaml`).
- **`@Native` resolution**: FFI functions use `@Native` annotations with `@DefaultAsset('package:zenoh/src/bindings.dart')`. The Dart runtime resolves `libzenoh_dart.so` via build hook metadata — no `DynamicLibrary.open()`. The OS linker resolves `libzenohc.so` automatically via the `DT_NEEDED` entry.
- **Build hook**: `packages/zenoh/hook/build.dart` registers two `CodeAsset` entries (libzenoh_dart.so and libzenohc.so) from `packages/zenoh/native/linux/x86_64/`.

### Dynamic Library Names by Platform

- macOS/iOS: `libzenoh_dart.dylib`
- Android/Linux: `libzenoh_dart.so`
- Windows: `zenoh_dart.dll`

### Version Constraints

- Dart SDK: ^3.11.0
- CMake: 3.10+

## Linting

Uses `lints` package (configured in `packages/zenoh/analysis_options.yaml`).

## TDD Workflow Plugin

This project uses the **tdd-workflow** Claude Code plugin for structured
test-driven development. The plugin provides specialized agents that
collaborate through a RED -> GREEN -> REFACTOR cycle.

### Plugin Architecture

| Agent | Role | Mode |
|-------|------|------|
| **tdd-planner** | Full planning lifecycle: research, decompose, present for approval, write .tdd-progress.md and planning/ archive | Read-write (approval-gated) |
| **tdd-implementer** | Writes tests first, then implementation, following the plan | Read-write |
| **tdd-verifier** | Runs the complete test suite and static analysis to validate each phase | Read-only |
| **tdd-releaser** | Finalizes completed features: CHANGELOG, push, PR creation | Read-write (Bash only) |

### Available Commands

- **`/tdd-plan <feature description>`** — Create a TDD implementation plan
- **`/tdd-implement`** — Start or resume TDD implementation for pending slices
- **`/tdd-release`** — Finalize and release a completed TDD feature

> **Important:** Do NOT manually invoke `tdd-workflow:tdd-planner` via the Task
> tool. It is designed to run through `/tdd-plan`, which provides the structured
> planning process. Manual invocation produces degraded results because the
> agent's 10-step process (from the skill definition) is absent.

### Four-Session Workflow

This project uses a four-session role pattern for structured development:

| Session | Role | Commands | Scope |
|---------|------|----------|-------|
| **CA** | Architect / Reviewer | None (read-only) | Decisions, issues, memory, plan review, PR verification |
| **CP** | Planner | `/tdd-plan` | Slice decomposition, plan iteration |
| **CI** | Implementer | `/tdd-implement`, `/tdd-release`, `/tdd-finalize-docs` | Code, tests, releases, direct edits |
| **CB** | Packaging Advisor | None (read-only) | Build, cross-compilation, distribution, pub.dev |

**Memory model:** CA is the sole memory writer. CP, CI, and CB read only.

See `docs/dev-roles/` for session prompts:
- `ca-architect.md` — architect/reviewer role
- `cp-planner.md` — planner role
- `ci-implementer.md` — implementer role
- `cb-packaging.md` — packaging advisor role

### Session State

If `.tdd-progress.md` exists at the project root, a TDD session is in progress.
Read it to understand the current state before making changes.

## TDD Guidelines

You are an expert Dart and C developer fluent in TDD, building a pure Dart FFI
package that wraps zenoh-c via a C shim layer.

### Architecture Awareness

This project has a three-layer architecture. Tests must respect it:

1. **C shim** (`src/zenoh_dart.{h,c}`) — thin wrappers flattening zenoh-c macros
2. **Generated FFI bindings** (`packages/zenoh/lib/src/bindings.dart`) — auto-generated, never tested directly
3. **Idiomatic Dart API** (`packages/zenoh/lib/src/*.dart`) — the public surface users consume

Test the Dart API layer. The C shim is validated indirectly through the Dart
tests calling through FFI into the real native code — these are integration
tests by nature. Do NOT mock the FFI layer; call through to the real
`libzenohc.so` and `libzenoh_dart.so`.

### Reference Architecture for API Design

Our dependency chain is: **Rust (zenoh core) → zenoh-c (C bindings) →
C shim (zd_*) → Dart FFI → Dart API**. We reference two layers:

- **zenoh-c** is our contract boundary. Every function we call, every
  options struct we fill, every return code we check is defined here.
  The C headers and tests are the authoritative spec.
- **zenoh-cpp** is our structural peer. It wraps the same zenoh-c API
  from another language, making it the best template for API design
  (options classes, error handling, Session vs Publisher split).

Do NOT reference the Rust source (`eclipse-zenoh/zenoh`) during planning
or implementation. It is one layer too deep — we cannot call Rust APIs,
only C APIs. The Rust codebase would overwhelm planning context and is
the wrong abstraction level. If a specific phase hits ambiguity that
zenoh-c and zenoh-cpp cannot resolve, escalate to CA for ad-hoc
investigation.

### Reference Tests in Submodules

The `extern/zenoh-c/tests/` and `extern/zenoh-cpp/tests/` directories contain
tests that serve as both behavioral specifications and structural templates:

- **zenoh-c unit tests** (`z_api_*.c`) validate the same C APIs our shim wraps.
  Use them to understand expected return codes, error conditions, and correct
  argument passing for each zenoh-c function.
- **zenoh-c integration tests** (`z_int_*.c`) demonstrate multi-endpoint
  patterns (pub/sub, queryable/get) including payload validation and QoS.
- **zenoh-cpp network tests** (`universal/network/*.cxx`) are the closest
  analog to our Dart tests — they're a language binding testing against
  zenoh-c, using two sessions in the same process. Mirror their structure
  when writing Dart pub/sub and queryable tests.
- **zenoh-c memory safety tests** (`z_api_double_drop_test.c`,
  `z_api_null_drop_test.c`) define the drop/cleanup contracts our `dispose()`
  methods must uphold.

When planning a phase, read the corresponding zenoh-c test (e.g.,
`z_api_payload_test.c` for bytes, `z_int_pub_sub_test.c` for pub/sub) to
understand what behaviors to verify and what edge cases to cover.

### Cross-Language API Parity Check

Before finalizing a phase plan or implementation, verify the Dart API against
the C and C++ equivalents in the extern submodules. This catches missing
semantics that the phase doc may not spell out explicitly.

**During planning (tdd-planner)**, read these for each new C shim function:

1. **C options struct** — Find `z_<operation>_options_t` in
   `extern/zenoh-c/include/zenoh_commons.h`. List every field. Confirm which
   fields the current phase exposes and which are explicitly deferred (NULL
   options = defaults). Document deferred fields in the plan so future phases
   know what remains.
2. **C move/consume semantics** — Check `extern/zenoh-c/tests/z_api_drop_options.c`
   and similar tests. Identify which parameters are consumed by `z_*_move()`.
   Every consumed parameter needs a corresponding `markConsumed()` call in
   Dart. When multiple parameters are consumed in one call (e.g., payload +
   attachment in `z_put`), the plan must account for all of them.
3. **C++ wrapper** — Read the corresponding method in
   `extern/zenoh-cpp/include/zenoh/api/session.hxx` (or `publisher.hxx`,
   `queryable.hxx`, etc.). Note the C++ options class fields and whether the
   Session-level and Publisher-level APIs differ. The Dart API should follow
   the same split when both levels exist.

**During implementation (tdd-implementer)**, verify:

4. **Return code semantics** — zenoh-c returns 0 on success, negative on
   error. Use `!= 0` consistently in Dart (not `< 0`), since this is
   defensive against future positive error codes.
5. **Error handling parity** — C++ throws `ZException` with a message and
   error code. Dart must throw `ZenohException` with equivalent information.
   Read the C++ `__ZENOH_RESULT_CHECK` macro messages for consistent wording.
6. **Cleanup on all paths** — If a C++ method has RAII cleanup (destructors
   on scope exit), the Dart equivalent needs explicit `try/finally` or helper
   methods (like `_withKeyExpr`) to guarantee the same cleanup.

**Quick reference — what to read per phase:**

| What | Where |
|------|-------|
| C options structs | `extern/zenoh-c/include/zenoh_commons.h` — search `z_<op>_options_t` |
| C move semantics | `extern/zenoh-c/tests/z_api_drop_options.c` |
| C examples | `extern/zenoh-c/examples/z_<op>.c` |
| C++ Session API | `extern/zenoh-cpp/include/zenoh/api/session.hxx` |
| C++ Publisher API | `extern/zenoh-cpp/include/zenoh/api/publisher.hxx` |
| C++ tests | `extern/zenoh-cpp/tests/universal/network/*.cxx` |

### Phase Docs as Source of Truth

Each phase spec in `docs/phases/phase-NN-*.md` defines:
- Exact C shim functions to add (signatures and which zenoh-c APIs they wrap)
- Exact Dart API surface (classes, methods, constructor signatures)
- CLI examples to create (`packages/zenoh/example/z_*.dart`)
- Verification criteria

Use the phase doc as your specification. Do not invent API surface beyond
what the phase doc describes. If the phase doc says "no new files needed",
don't create new files.

### Slice Decomposition Principles

- **One slice = one testable behavior**, not one function. A C shim function
  plus its Dart wrapper plus the test is ONE slice if they serve one behavior.
- **C shim and Dart wrapper in the same slice** — don't split the C shim into
  its own slice. The shim has no independent test harness; it's verified
  through the Dart test.
- **CLI examples get their own slice** — they're independently testable
  (process runs, produces expected output).
- **Build system changes are a setup step**, not a slice. CMakeLists.txt and
  ffigen.yaml changes go in the first slice as prerequisites.

### What "Not Over-Engineered" Means Here

- No abstract base classes or interfaces for types that have one implementation
- No builder patterns — use named constructors and simple factory methods
- No dependency injection frameworks — pass dependencies as constructor args
- `dispose()` methods for types holding native memory, nothing more
- Error handling: check return codes, throw `ZenohException` on failure
- Don't add encoding, QoS options, or attachment parameters until the phase
  doc calls for them (later phases add options progressively)

### Testing Constraints

- Tests require `libzenohc.so` and `libzenoh_dart.so` to be built and
  placed in `packages/zenoh/native/linux/x86_64/`. Build hooks register
  these as code assets for `@Native` resolution.
- Session-based tests need a zenoh router or peer — use `Session.open()` with
  default config (peer mode) for unit tests. Tests that need two endpoints
  (pub/sub, get/queryable) open two sessions in the same process.
- Keep tests fast: open session once per group, not per test.
- Test file placement: `packages/zenoh/test/` mirroring `packages/zenoh/lib/src/` (e.g., `test/session_test.dart`).

### Commit Scope Naming

Use the primary Dart module as `<scope>` in commit messages:
- `test(session): ...`, `feat(session): ...`
- `test(keyexpr): ...`, `feat(keyexpr): ...`
- `test(z-put): ...` for CLI examples

## Documentation Finalization Guide

When `/tdd-finalize-docs` runs after a release, update these specific sections:

### CLAUDE.md updates
1. **"Current Status" section** — Add a status line for the completed phase: `**Phase N Name: COMPLETE** — X C shim functions, Y integration tests. <brief description>.`
2. **"Available Dart API classes" list** — Add new classes with one-line descriptions. Keep alphabetical by category (static utils, config, session, data types, exceptions).
3. **"CLI examples" code block** — Add new CLI examples (no `LD_LIBRARY_PATH` needed — build hooks resolve automatically). Include a comment describing what the command does. Verify ALL existing CLI examples are present (check `packages/zenoh/example/z_*.dart` against the code block).
4. **"Phases N–18" line** — Update the starting phase number.

### README.md updates
1. **Architecture diagram** — Update the top-line class list in the ASCII diagram.
2. **Phase status blocks** — Add a new status block for the completed phase with: C shim function count, new API surface, CLI example, test count.
3. **"Phases N–18" line** — Update the starting phase number.
4. **"CLI Examples" section** — Add new CLI commands (no `LD_LIBRARY_PATH` needed). Verify ALL existing CLI examples are present (check `packages/zenoh/example/z_*.dart`).
5. **"Phase Roadmap" table** — Mark the completed phase row with `— **COMPLETE**`.

### Verification checklist
- Cross-check `packages/zenoh/example/z_*.dart` against CLI example sections in both CLAUDE.md and README.md — every CLI binary must be documented.
- Cross-check `packages/zenoh/lib/zenoh.dart` exports against "Available Dart API classes" — every exported class/enum must be listed.
- Run `fvm dart analyze packages/zenoh` to confirm no issues.

## Session Directives

When /tdd-plan completes, always show the FULL plan text produced by the planner agent — every slice with Given/When/Then, acceptance criteria, phase tracking, and dependencies. Never summarize or abbreviate the plan output.
