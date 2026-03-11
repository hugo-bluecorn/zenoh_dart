# CA Review: Inter-Process Crash Fix (2026-03-11)

## What CI Did (8 commits on `feature/fix-rtld-local-interprocess-crash`)

| Commit | Description |
|---|---|
| `0412090` | Added `zd_promote_zenohc_global()` (wrong fix, Slice 1 of old plan) |
| `2df31a0` | Inter-process test infrastructure (helpers + skipped tests) |
| `ab77d5f` | Lint fixes on test docs |
| `292f0a3` | Tests for DynamicLibrary.open() pre-load |
| `a9e6625` | Attempted hybrid pre-load (keep @Native + add DynamicLibrary.open) |
| `93e29e5` | **Key commit**: Reverted @Native entirely, back to class-based `ZenohDartBindings(DynamicLibrary)` |
| `15cae58` | Cleaned up redundant `ensureInitialized()` calls |
| `62a5995` | Added pub/sub data exchange tests |

## Deviations from Plan

| Plan said | CI did | Assessment |
|---|---|---|
| Keep @Native, pre-load via DynamicLibrary.open() | Reverted @Native entirely | **Correct** — the hybrid approach didn't work either. @Native's `NoActiveIsolateScope` taints the handle even after pre-load. |
| Option C path resolution (.dart_tool/lib/) | Uses `Isolate.resolvePackageUriSync()` + prefers `native/linux/x86_64/` over `.dart_tool/lib/` | **Better than planned** — avoids loading from the tainted `.dart_tool/lib/` path |
| 13 new tests | 8 new tests (6 in native_lib_test + 4 interprocess connect + 3 interprocess pubsub = 13, but test runner reports 193 total = 185 + 8 net new) | The native_lib_test tests likely replaced existing promote_test ones. Net count is correct. |

## Compliance with Dart/Flutter Package Guidelines

**1. Build hooks still register CodeAssets** — `hook/build.dart` is unchanged. The hook still declares both libraries as `DynamicLoadingBundled` code assets. This is needed for `pub.dev` distribution and Flutter engine integration. **Compliant.**

**2. Build hook comment updated** — `hook/build.dart` comment now says "bundled for distribution; loaded at runtime via DynamicLibrary.open()". **Fixed.**

**3. ffigen.yaml removed `ffi-native` config** — Correct. Without @Native, the `ffi-native` block (which generated `@Native` annotations) must be removed. The bindings now generate class-based `ZenohDartBindings(DynamicLibrary)` instead. **Compliant.**

**4. `native_lib.dart` exposes `bindings` getter** — All call sites use `bindings.zd_*()` instead of the old `ffi_bindings.zd_*()` top-level calls. Clean pattern. **Compliant.**

**5. No public API changes** — `zenoh.dart` barrel exports unchanged. No classes/methods added or removed from the public surface. **Compliant.**

**6. Build hooks + DynamicLibrary.open() coexistence** — The build hook copies .so files to `.dart_tool/lib/` for distribution. `native_lib.dart` loads from `native/linux/x86_64/` (development prebuilts) with fallback to `.dart_tool/lib/` (hook output). This is a valid pattern — the hook handles *bundling*, DynamicLibrary.open() handles *loading*. **Compliant, but unconventional.** Most hook-based packages use @Native. This is a workaround for a Dart VM bug.

**7. CodeAsset registrations are now orphaned** — The hook registers `src/bindings.dart` and `src/zenohc.dart` as asset IDs, but no `@Native` annotation references them. The assets are still bundled (the .so files get copied) but the Dart VM's native asset resolver never looks them up. The hook effectively serves as a file-copy mechanism only. **Functional but semantically misleading.** This works because the build hook runs regardless of whether @Native references exist — it's triggered by the `hooks` package dependency, not by @Native annotations.

## Verdict

**Approved.** The architectural decision to revert @Native is correct — it's the only thing that works. The fix is clean, well-tested, and the manual smoke test confirmed it.

## Investigation Timeline Summary

1. Original hypothesis: RTLD_LOCAL symbol visibility → `zd_promote_zenohc_global()` fix
2. CI implemented promote fix → inter-process tests still crashed
3. CA investigation: LD_PRELOAD also doesn't fix it (original investigation's LD_PRELOAD finding was wrong — no actual TCP connection in that test)
4. Definitive A/B test: `DynamicLibrary.open()` (pre-PR#18 code) works; `@Native` (post-PR#18) crashes. Same .so, same SDK, same machine.
5. Dart SDK source analysis: `@Native` uses `NoActiveIsolateScope` (thread-isolate detachment during dlopen) + lazy `FfiResolve`. `DynamicLibrary.open()` does not.
6. CI attempted hybrid pre-load (DynamicLibrary.open + keep @Native) → still crashed
7. CI reverted @Native entirely → **fix confirmed**, 193/193 tests pass, manual pub/sub verified

## Key Files Changed

- `packages/zenoh/lib/src/native_lib.dart` — DynamicLibrary.open() with path discovery via `Isolate.resolvePackageUriSync()`
- `packages/zenoh/lib/src/bindings.dart` — Regenerated as class-based `ZenohDartBindings(DynamicLibrary)`, no @Native
- `packages/zenoh/ffigen.yaml` — Removed `ffi-native` config block
- `packages/zenoh/lib/src/*.dart` (10 files) — Changed `ffi_bindings.zd_*()` to `bindings.zd_*()`
- `src/zenoh_dart.{h,c}` — Removed `zd_promote_zenohc_global()`
- `packages/zenoh/test/interprocess_test.dart` — 7 new inter-process tests
- `packages/zenoh/test/helpers/interprocess_connect.dart` — Connection helper
- `packages/zenoh/test/helpers/interprocess_pubsub.dart` — Pub/sub helper
- `packages/zenoh/test/native_lib_test.dart` — 6 tests replacing promote_test.dart
