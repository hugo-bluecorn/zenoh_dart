# Hooks Bundling Experiment Synthesis

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Complete
> **Artifacts**: PRs #13–#17, 5 experiment packages, 37 automated tests

## Abstract

We set out to answer a single question: *How should zenoh-dart bundle its
two native libraries (`libzenoh_dart.so` + `libzenohc.so`) using Dart build
hooks so that consumers never touch `LD_LIBRARY_PATH`?*

We designed a controlled 2×2 experiment varying two independent dimensions
— build strategy (prebuilt vs CBuilder) and loading mechanism
(`DynamicLibrary.open()` vs `@Native` annotations) — and tested each
combination in isolation. A fifth experiment verified the winning approach
from an external consumer project created with `dart create`.

The results are unambiguous.

## The 2×2 Matrix

```
                  DynamicLibrary.open()          @Native annotations
              ┌──────────────────────────┬──────────────────────────┐
  Prebuilt    │  A1: NEGATIVE (PR #13)   │  A2: POSITIVE (PR #14)  │
              ├──────────────────────────┼──────────────────────────┤
  CBuilder    │  B1: NEGATIVE (PR #15)   │  B2: POSITIVE (PR #16)  │
              └──────────────────────────┴──────────────────────────┘

  Consumer    │  A2 as dependency: PASS (PR #17)                    │
              └─────────────────────────────────────────────────────┘
```

**Loading mechanism is the sole determinant of success.** Build strategy
is orthogonal. Every `DynamicLibrary.open()` experiment fails identically;
every `@Native` experiment succeeds identically.

## Why DynamicLibrary.open() Fails

`DynamicLibrary.open('libzenoh_dart.so')` delegates entirely to the OS
dynamic linker (`ld.so` on Linux). The OS linker searches `LD_LIBRARY_PATH`,
`RUNPATH`, `/etc/ld.so.cache`, and `/usr/lib` — none of which contain
hook-bundled assets. The Dart build hook writes metadata to
`.dart_tool/hooks_runner/`, but `ld.so` does not read Dart metadata. It
never will. These are separate systems with no integration point.

The failure is architectural, not a bug to be fixed.

## Why @Native Succeeds

`@Native` annotations are resolved by the **Dart runtime**, not the OS
linker. The runtime reads the hook output metadata (the same
`.dart_tool/hooks_runner/` files that `ld.so` ignores), maps the
`@DefaultAsset` URI to the registered `CodeAsset` file path, and loads
the library directly by absolute path. The OS linker is bypassed for
discovery — it only participates in symbol resolution after the library
is loaded.

The DT_NEEDED dependency (`libzenohc.so`) resolves through the OS linker's
RUNPATH mechanism (`$ORIGIN`), because by the time the OS linker processes
DT_NEEDED, the primary library has already been loaded from a known
directory. Both `.so` files are co-located in that directory (placed there
by the hook's `DynamicLoadingBundled()` declaration), so `$ORIGIN` finds
the dependency.

## Quantitative Results

| Metric | A1 | A2 | B1 | B2 | Consumer |
|--------|----|----|----|----|----------|
| Tests pass (no LD_LIBRARY_PATH) | 2/7 | 9/9 | 6/11 | 10/10 | 1/1 |
| Tests skipped (expected negative) | 5 | 0 | 5 | 0 | 0 |
| `dart run` exit code | 255 | 0 | 1 | 0 | 0 |
| `dart test` exit code | 0 | 0 | 0 | 0 | — |
| Hook build succeeds | Yes | Yes | Yes | Yes | Yes (transitive) |
| RUNPATH correct | No* | Yes† | Yes‡ | Yes‡ | Yes |
| Cold build time | ~0.3s | ~0.3s | ~1.0s | ~1.0s | ~0.3s |

\* Absolute build-machine path baked in by CMake.
† After `patchelf --set-rpath '$ORIGIN'`.
‡ CBuilder sets `$ORIGIN` automatically.

## Key Discoveries

### 1. CodeAsset names must be bare relative paths

The `CodeAsset` constructor auto-prefixes `package:<packageName>/` to the
`name` parameter. Passing a full `package:` URI produces a double-prefixed
asset ID (`package:foo/package:foo/src/bindings.dart`) that breaks `@Native`
resolution silently. This is undocumented. Discovered empirically in A2.

**Rule**: Always use bare relative paths like `src/bindings.dart`.

### 2. RUNPATH patching is mandatory for prebuilt libraries

Developer-built `.so` files have the build machine's absolute path baked
into RUNPATH by CMake. This path is meaningless on any other machine.
Prebuilt `.so` files must be patched before bundling:

```bash
patchelf --set-rpath '$ORIGIN' libzenoh_dart.so
```

CBuilder sets `$ORIGIN` RUNPATH automatically, eliminating this step.

### 3. Two CodeAsset entries are required

Even though only `libzenoh_dart.so` has `@Native` symbols,
`libzenohc.so` must also be registered as a `CodeAsset` with
`DynamicLoadingBundled()`. The Dart tooling only copies/places
registered assets into the runtime-accessible location. Without
registration, `libzenohc.so` would not be co-located with
`libzenoh_dart.so` and DT_NEEDED resolution would fail.

### 4. Build hooks run twice (cosmetic)

Every `dart run` and `dart test` invocation prints "Running build
hooks..." twice. This appears to be the hook system processing each
package with hooks in the dependency graph. No functional impact, but
visible to users.

### 5. Post-test SEGV during VM teardown (cosmetic)

The Dart VM occasionally crashes with `SEGV_MAPERR` during process
teardown after tests complete. This is a zenoh native library cleanup
ordering issue (zenoh-c tears down resources in an order that conflicts
with the VM's exit sequence). All tests pass before the crash, and the
test runner reports exit code 0. Not related to the hooks mechanism.

### 6. Hooks work transitively from external consumers

The consumer test (PR #17) proved that a standalone `dart create` project
depending on a hooked package via path dependency gets the same
transparent native library resolution. The build hook fires transitively
during the consumer's `dart run`. This is the critical proof that the
mechanism works for published packages, not just in-package development.

## Build Strategy Trade-offs

Both build strategies produce correct results when paired with `@Native`.
The choice between them is a trade-off:

### A2: Both-prebuilt

| Advantage | Detail |
|-----------|--------|
| Simplicity | No `native_toolchain_c` dependency |
| Stability | Only stable dependencies (`hooks`, `code_assets`) |
| Speed | ~0.3s cold build (file copy only) |
| No vendoring | Zero header files to maintain |

| Disadvantage | Detail |
|--------------|--------|
| RUNPATH patching | Manual `patchelf` step per platform |
| Binary blobs | ~15MB of `.so` files in package source |
| Per-platform builds | Must pre-build for each target (Linux x86_64, arm64, Android ABIs) |
| No source reproducibility | Consumer trusts the prebuilt binary |

### B2: CBuilder + prebuilt

| Advantage | Detail |
|-----------|--------|
| Automatic RUNPATH | CBuilder sets `$ORIGIN` — no patchelf |
| Source reproducibility | C shim compiled from vendored source |
| Cross-compilation | CBuilder integrates with NDK toolchains |
| Dependency tracking | Recompiles only when source/headers change |

| Disadvantage | Detail |
|--------------|--------|
| EXPERIMENTAL dependency | `native_toolchain_c` ^0.17.5 |
| Header vendoring | 15 files (8 zenoh-c + 6 Dart SDK + 1 project) |
| Compilation overhead | ~1.0s cold, ~0.3s warm |
| Compiler required | Consumer needs a C compiler on PATH |

### Recommendation

**Use A2 (both-prebuilt + @Native) for the initial migration.** Rationale:

1. **Stability**: `native_toolchain_c` is explicitly marked EXPERIMENTAL.
   The initial hooks migration should use only stable dependencies.

2. **Consumer experience**: Prebuilt means `dart pub add zenoh` + `dart run`
   just works — no C compiler required. This is the pub.dev experience we
   want.

3. **Simplicity**: The hook is 15 lines of Dart. No compilation logic, no
   include path management, no linker flag plumbing.

4. **RUNPATH is solvable**: A single `patchelf` command in the build script
   is a one-time automation, not ongoing friction.

5. **CBuilder remains available**: If `native_toolchain_c` reaches 1.0 and
   cross-compilation becomes a priority (Android NDK), B2 is a proven
   fallback that requires only swapping the hook — no Dart API changes,
   no test changes.

**The only library that needs prebuilding for each platform is
`libzenohc.so`** (14.6MB, built from Rust). `libzenoh_dart.so` (49KB)
is our thin C shim. For a CBuilder future, only `libzenohc.so` stays
prebuilt — the shim compiles from source. This hybrid (CBuilder for shim
+ prebuilt for zenoh-c) is exactly what cbl-dart does in production.

## Migration Path for packages/zenoh/

### Required changes

1. **Add `hook/build.dart`** — Two `CodeAsset` entries with
   `DynamicLoadingBundled()`. Primary asset name matches the
   `@DefaultAsset` URI in the bindings library.

2. **Regenerate bindings with `@Native` output** — Configure ffigen to
   emit `@Native` annotations instead of `DynamicLibrary`-based bindings.
   This is a single ffigen.yaml config change.

3. **Add `@DefaultAsset` library directive** — To the generated bindings
   file (or a wrapper that re-exports it).

4. **Remove `DynamicLibrary.open()` from `native_lib.dart`** — Replace
   the single-load pattern with `@Native` resolution. The entire
   `native_lib.dart` may become unnecessary if ffigen generates the
   `@DefaultAsset` directive directly.

5. **Add prebuilt `.so` files** — To `native/linux/x86_64/` (and
   eventually per-platform directories). Patch RUNPATH to `$ORIGIN`.

6. **Add dependencies** — `hooks: ^1.0.0`, `code_assets: ^1.0.0` to
   `pubspec.yaml` (in `dependencies`, not `dev_dependencies`).

7. **Remove `LD_LIBRARY_PATH`** — From all test commands, CLI examples,
   and documentation. This is the user-visible payoff.

### What does NOT change

- The C shim source (`src/zenoh_dart.{h,c}`)
- The public Dart API (`packages/zenoh/lib/zenoh.dart` exports)
- Test files (they call the Dart API, not FFI directly)
- CLI examples (they import the public API)
- CMake build system (still needed for developer builds)

## Conclusion

The five experiments produced a clean, reproducible result: **`@Native`
annotations are mandatory for Dart build hooks, and
`DynamicLibrary.open()` is incompatible with them.** The build strategy
is a free choice — both prebuilt and CBuilder work. The consumer test
confirmed the mechanism works transitively from external projects.

The migration from `DynamicLibrary.open()` to `@Native` + build hooks
will eliminate `LD_LIBRARY_PATH` from every command in the project. For
users, `dart pub add zenoh` followed by `dart run` will just work.

That is the entire point.
