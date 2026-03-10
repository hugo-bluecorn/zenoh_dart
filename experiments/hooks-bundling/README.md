# Dart Build Hooks Experiment: Two-Library Native Bundling

## Problem

zenoh-dart ships **two** native shared libraries:

| Library | Source | Role |
|---------|--------|------|
| `libzenoh_dart.so` | C shim (`src/zenoh_dart.c`) | Wraps zenoh-c macros and inline functions that Dart FFI cannot call directly |
| `libzenohc.so` | zenoh-c v1.7.2 (Rust via Cargo) | The zenoh runtime |

`libzenoh_dart.so` depends on `libzenohc.so` via a `DT_NEEDED` ELF entry.
Both must be co-located and loadable at runtime.

Today, developers must manually set `LD_LIBRARY_PATH` to point at both
libraries. This works for development but is not viable for distribution
via pub.dev or for Flutter app consumers who expect `flutter pub add zenoh`
to just work.

## Goal

Determine the best way to use [Dart build hooks](https://dart.dev/tools/hooks)
(stable since Dart 3.10 / Flutter 3.38) to bundle both libraries
automatically, eliminating `LD_LIBRARY_PATH` for consumers.

## Approach: Controlled 2x2 Experiment

We identified **two independent variables** that affect how hooks bundling
works:

1. **Build strategy** — Should both libraries be prebuilt, or should the
   C shim be compiled from source at build time using `CBuilder`?
2. **Loading mechanism** — Should Dart code use `DynamicLibrary.open()`
   (our current approach) or `@Native` annotations (the hooks-native
   resolution path)?

Rather than guessing, we test all four combinations in isolated packages
within this monorepo:

| | `DynamicLibrary.open()` | `@Native` annotations |
|---|---|---|
| **Both prebuilt** | [A1](spec-a1-prebuilt-dlopen.md) | [A2](spec-a2-prebuilt-native.md) |
| **CBuilder + prebuilt** | [B1](spec-b1-cbuilder-dlopen.md) | [B2](spec-b2-cbuilder-native.md) |

Each experiment:
- Lives in its own package under `packages/`
- Changes exactly **one variable** from its neighbors
- Tests the same 6 verification criteria
- Records results in a `lessons-learned.md`

The existing `packages/zenoh/` package is the **control** — untouched
throughout.

## Why This Matters

Our research (documented in [design.md](design.md)) found a critical
gap: **`DynamicLibrary.open('libfoo.so')` does NOT automatically find
hook-bundled assets**. The Dart runtime resolves `@Native`-annotated
functions via asset ID mapping from the build hook's `CodeAsset`
declarations — a completely different resolution path than the OS dynamic
linker.

This means the choice of loading mechanism is not cosmetic — it may
determine whether hooks bundling works at all. The experiment will produce
empirical evidence for or against each combination.

## Verification Criteria

Each experiment is tested against:

1. Does `dart run` find bundled libs? (no `LD_LIBRARY_PATH`)
2. Does `dart test` find bundled libs? (no `LD_LIBRARY_PATH`)
3. Does `flutter run` find bundled libs? (test Flutter app)
4. Does the `DT_NEEDED` dependency between the two libs resolve?
5. Does the hook build succeed on Linux x86_64?
6. Is error reporting adequate when something fails?

Negative results are equally valuable — a failed experiment proves that
a combination is not viable and narrows the decision space.

## Key Research Findings

| Finding | Source |
|---------|--------|
| Two-library bundling is supported | [dart-lang/native#190](https://github.com/dart-lang/native/issues/190) (CLOSED) |
| macOS install_name rewriting works | [Flutter PR #153054](https://github.com/flutter/flutter/pull/153054) (MERGED) |
| Linux RPATH must be set at compile time | [dart-lang/native#190 discussion](https://github.com/dart-lang/native/issues/190) |
| `native_toolchain_c` (CBuilder) is experimental | [pub.dev](https://pub.dev/packages/native_toolchain_c) |
| `dart test` runs hooks since Dart 3.10 | [dart.dev/tools/hooks](https://dart.dev/tools/hooks) |
| Hook error reporting is poor | [dart-lang/native#1966](https://github.com/dart-lang/native/issues/1966) (OPEN) |
| cbl-dart uses CBuilder + prebuilt (production) | [cbl-dart/cbl-dart](https://github.com/cbl-dart/cbl-dart) |
| sqlite3 uses prebuilt download (canonical) | [simolus3/sqlite3.dart](https://github.com/simolus3/sqlite3.dart) |

Full research details: [design.md](design.md) (Research Findings section).

## Documentation Index

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | This file — experiment overview and entry point |
| [context.md](context.md) | Self-contained project context (cold-start for new readers) |
| [design.md](design.md) | Full design doc with research findings and experiment plan |
| [prior-analysis.md](prior-analysis.md) | Original A/B/C package analysis (superseded, kept for provenance) |
| [spec-a1-prebuilt-dlopen.md](spec-a1-prebuilt-dlopen.md) | Experiment A1 spec |
| [spec-a2-prebuilt-native.md](spec-a2-prebuilt-native.md) | Experiment A2 spec |
| [spec-b1-cbuilder-dlopen.md](spec-b1-cbuilder-dlopen.md) | Experiment B1 spec |
| [spec-b2-cbuilder-native.md](spec-b2-cbuilder-native.md) | Experiment B2 spec |

Results (created during implementation):

| Document | Purpose |
|----------|---------|
| `packages/exp_hooks_prebuilt_dlopen/lessons-learned.md` | A1 results |
| `packages/exp_hooks_prebuilt_native/lessons-learned.md` | A2 results |
| `packages/exp_hooks_cbuilder_dlopen/lessons-learned.md` | B1 results |
| `packages/exp_hooks_cbuilder_native/lessons-learned.md` | B2 results |

## SDK Versions

- Dart 3.11.0 / Flutter 3.41.4 (via FVM)
- zenoh-c v1.7.2
- `hooks` ^1.0.0, `code_assets` ^1.0.0
- `native_toolchain_c` ^0.17.5 (B1/B2 only, experimental)
