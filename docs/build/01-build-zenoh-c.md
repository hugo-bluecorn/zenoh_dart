# Build zenoh-c with Clang (standalone, Linux)

## Context

The `zenoh_dart` Flutter FFI plugin has a `extern/zenoh-c` git submodule (v1.7.2, eclipse-zenoh/zenoh-c main branch). zenoh-c is a C API wrapper around Rust zenoh -- CMake orchestrates Cargo underneath. This document covers building it standalone with clang on Linux. Flutter plugin integration will be a separate follow-up.

## Prerequisites

| Tool | Minimum version | Tested version |
|------|----------------|---------------|
| clang/clang++ | any recent | 18.1.3 |
| cmake | 3.10+ | 3.28.3 |
| ninja | any | 1.11.1 |
| rustc/cargo | 1.75.0 (MSRV) | 1.92.0 |

## Rust toolchain workaround

`extern/zenoh-c/rust-toolchain.toml` pins channel `1.93.0` (unreleased at the time of this build). We set `RUSTUP_TOOLCHAIN=stable` to override this and use the installed stable toolchain instead. This is safe because zenoh-c's MSRV is 1.75.0.

## Steps

### 1. Configure

```bash
cmake \
  -S extern/zenoh-c \
  -B extern/zenoh-c/build \
  -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=TRUE \
  -DZENOHC_BUILD_IN_SOURCE_TREE=TRUE
```

Key flags:
- `-DZENOHC_BUILD_IN_SOURCE_TREE=TRUE` -- places `target/` inside the submodule (not a detached build dir)
- `-DBUILD_SHARED_LIBS=TRUE` -- produces `libzenohc.so` (needed for FFI)

### 2. Build

```bash
RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --config Release
```

First build takes ~2-10 minutes depending on hardware. Subsequent builds are incremental.

### 3. Verify

```bash
# Check shared library
file extern/zenoh-c/target/release/libzenohc.so
# Expected: ELF 64-bit LSB shared object, x86-64

# Check exported symbols
nm -D extern/zenoh-c/target/release/libzenohc.so | grep "T z_" | wc -l
# Expected: ~477 symbols

# Check headers compile
clang -fsyntax-only -I extern/zenoh-c/include -xc - <<< '#include "zenoh.h"'
```

### 4. Run tests

```bash
RUSTUP_TOOLCHAIN=stable cmake --build extern/zenoh-c/build --target tests
ctest --test-dir extern/zenoh-c/build -R "^(unit|build)_" --output-on-failure
```

Expected: 12/14 pass. Two tests (`unit_z_api_alignment_test`, `unit_z_api_liveliness`) are known flaky due to timing-dependent assertions in the upstream zenoh-c test suite.

## Build artifacts

| Artifact | Path |
|----------|------|
| Shared library | `extern/zenoh-c/target/release/libzenohc.so` |
| Static library | `extern/zenoh-c/target/release/libzenohc.a` |
| Headers | `extern/zenoh-c/include/zenoh.h` (umbrella) |
| CMake build dir | `extern/zenoh-c/build/` |
| Cargo target dir | `extern/zenoh-c/target/` |

All build artifacts are in `.gitignore`.

## Clean build

```bash
rm -rf extern/zenoh-c/build extern/zenoh-c/target
```
