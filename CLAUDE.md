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

# Run tests (requires native libs on LD_LIBRARY_PATH)
cd packages/zenoh && fvm dart test

# Melos bootstrap (from monorepo root)
fvm dart run melos bootstrap
```

## Architecture

### FFI Package Structure

Native C code in `src/` is compiled into a shared library and loaded at runtime via `dart:ffi`.

**Data flow:** Dart API (`packages/zenoh/lib/zenoh.dart`) → Generated bindings (`packages/zenoh/lib/src/bindings.dart`) → Native C (`src/zenoh_dart.{h,c}`) → `libzenohc.so` (resolved by OS linker via DT_NEEDED)

### Key Conventions

- **Short-lived native functions**: Call directly from any isolate (e.g., `zd_put()`)
- **Long-lived native functions**: Must run on a helper isolate to avoid blocking. Uses `SendPort`/`ReceivePort` request-response pattern with `Completer`-based futures.
- **Binding generation**: `packages/zenoh/lib/src/bindings.dart` is auto-generated — never edit manually. Regenerate with `fvm dart run ffigen --config ffigen.yaml` after changing `src/zenoh_dart.h`.
- **Single-load library**: Only `libzenoh_dart.so` is loaded explicitly in Dart. The OS linker resolves `libzenohc.so` automatically via the `DT_NEEDED` entry.

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

### Two-Session Workflow

This project uses a two-session review pattern for plan quality:
- **CZ session** — Runs `/tdd-plan` and `/tdd-implement`; performs all code work
- **CA session** — Read-only advisor that reviews plans before CZ approval

See `docs/tdd-prompts/ca-plan-advisor.md` for the CA session prompt.

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

### Phase Docs as Source of Truth

Each phase spec in `docs/phases/phase-NN-*.md` defines:
- Exact C shim functions to add (signatures and which zenoh-c APIs they wrap)
- Exact Dart API surface (classes, methods, constructor signatures)
- CLI examples to create (`packages/zenoh/bin/z_*.dart`)
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
  loadable. The test runner must find them (via `LD_LIBRARY_PATH` or rpath).
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
