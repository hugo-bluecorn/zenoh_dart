# Inter-Process Crash Investigation (2026-03-11)

## Bug Report: Inter-Process SIGSEGV/SIGBUS When Two Dart Processes Connect

### Problem Statement

After the hooks migration (PR #18), any two separate Dart processes that both
load `libzenohc.so` via `@Native` build hooks crash when they establish a TCP
connection via zenoh. The **listener** process crashes; the connector is fine.
No data transfer is required — just `Session.open()` with TCP listen/connect
on each side triggers the crash.

The crash was first observed running `zenoh-counter-dart`'s publisher and
subscriber in separate terminals. It also reproduces with zenoh-dart's own
`z_pub.dart` + `z_sub.dart` examples.

### Crash Signature

```
===== CRASH =====
si_signo=Segmentation fault(11), si_code=SEGV_MAPERR(1), si_addr=(nil)
pid=XXXX, thread=YYYY, isolate_group=(nil), isolate=(nil)
pc=0
```

- Crash on a **non-Dart thread** (isolate_group=nil) — a tokio worker thread
  inside libzenohc.so
- `pc=0` = null function pointer dereference

### GDB Stack Trace (Thread 19 "app-0")

```
#0  0x0000000000000000 in ?? ()
#1  tokio::runtime::io::scheduled_io::ScheduledIo::wake()  [libzenohc.so]
#2  tokio::runtime::io::driver::Driver::turn()              [libzenohc.so]
#3  tokio::runtime::time::Driver::park_internal()           [libzenohc.so]
#4  tokio::runtime::scheduler::multi_thread::worker::Context::park_internal()
#5  tokio::runtime::scheduler::multi_thread::worker::run()
...
#9  std::sys::thread::unix::Thread::new::thread_start()
```

The crash is in tokio's I/O event driver calling `ScheduledIo::wake()` with a
null waker function pointer. This is inside `libzenohc.so`'s Rust runtime, NOT
in our C shim or subscriber callback.

### Initial Investigation (Flawed)

**Systematic isolation via 6 inter-process test combinations:**

| Publisher | Subscriber | Result |
|-----------|-----------|--------|
| zenoh-c native (z_pub) | zenoh-c native (z_sub) | **PASS** |
| zenoh-c native (z_pub) | Dart (z_sub.dart) | **PASS** — 7 messages received |
| Dart (z_pub.dart) | zenoh-c native (z_sub) | **PASS** |
| Dart (z_pub.dart) | Dart (z_sub.dart) | **CRASH** — subscriber crashes |
| Dart (empty Session) | Dart (empty Session) | **CRASH** — listener crashes |
| Dart (LD_PRELOAD) | Dart (LD_PRELOAD) | **PASS** |

**Initial observations:**
- All 185 in-process tests pass (two sessions, same process, same tokio runtime)
- Crash requires TWO SEPARATE Dart processes connecting — no data needed
- zenoh-c native examples (compiled C, same libzenohc.so binary by md5sum) work
  fine in all combinations
- SHM transport disabled (`transport/shared_memory/enabled: false`) still crashes
- libzenohc.so rebuilt WITHOUT SHM features still crashes
- ~~`LD_PRELOAD=libzenohc.so` on both processes **completely fixes the crash**~~ (WRONG — see correction below)

**Library identity verified:**
```
md5sum extern/zenoh-c/target/release/libzenohc.so = 71384a9fca9ceb098c491c5176b4c447
md5sum packages/zenoh/native/linux/x86_64/libzenohc.so = 71384a9fca9ceb098c491c5176b4c447
```
Same binary in both locations.

### CORRECTION: LD_PRELOAD Finding Was Wrong

The initial investigation's LD_PRELOAD test (row 6 above) used **default config
with multicast peer discovery** — no explicit TCP listen/connect endpoints.
The two processes likely never established a real TCP connection. They appeared
to "pass" because neither crashed (and neither connected).

When re-tested with explicit TCP endpoints (`-l tcp/...` on subscriber,
`-e tcp/...` on publisher), **LD_PRELOAD does NOT fix the crash**.

### Definitive A/B Test (2026-03-11)

Using a git worktree at commit `9383af2` (pre-hooks, Phase 5 merge) to test
the old `DynamicLibrary.open()` approach against the current `@Native` approach.
Same .so binaries (md5sum verified), same Dart SDK (3.11.1), same machine.

| Loading Mechanism | LD env | TCP endpoints | Result |
|---|---|---|---|
| `DynamicLibrary.open()` (pre-PR#18) | LD_LIBRARY_PATH=native/ | -l / -e explicit | **WORKS** — messages received, clean exit |
| `@Native` + build hooks | none | -l / -e explicit | **CRASH** — tokio waker null ptr |
| `@Native` + build hooks | LD_PRELOAD=libzenohc.so | -l / -e explicit | **CRASH** |
| `@Native` + build hooks | LD_LIBRARY_PATH=native/ | -l / -e explicit | **CRASH** |
| `@Native` + build hooks | LD_LIBRARY_PATH=.dart_tool/lib/ | -l / -e explicit | **CRASH** |

**Conclusion: The crash is caused by `@Native`'s loading mechanism, not by
RTLD_LOCAL vs RTLD_GLOBAL symbol visibility.** No environment variable
workaround fixes the crash when `@Native` is the loading mechanism.

### Dart SDK Source Analysis

The Dart SDK source (`extern/dart-sdk/runtime/`) was examined to understand
the difference between `DynamicLibrary.open()` and `@Native`.

**Both call the same `dlopen(path, RTLD_LAZY)`** — confirmed in
`runtime/platform/utils.cc:304`. The dlopen flags are identical.

**Key differences found:**

1. **`NoActiveIsolateScope`** — `@Native` wraps every dlopen call in
   `NoActiveIsolateScope` (`runtime/lib/ffi_dynamic_library.cc:348-412`),
   which temporarily sets `thread->isolate_ = nullptr` during the dlopen.
   `DynamicLibrary.open()` does NOT use this scope (`ffi_dynamic_library.cc:168`).

2. **Lazy vs eager** — `@Native` resolves symbols lazily on first FFI call
   via `FfiResolveAsset()`. `DynamicLibrary.open()` loads eagerly, and
   `lookupFunction()` resolves all symbols upfront.

3. **Path type** — `@Native` uses absolute paths from the build hook asset
   manifest (via `dlopen_absolute`). `DynamicLibrary.open()` uses bare
   library names searched via LD_LIBRARY_PATH.

4. **Loading thread** — strace confirmed `@Native` loads on a different
   thread (pid 72205) than the main process. `DynamicLibrary.open()` loads
   on the app's isolate thread (pid 72987).

**strace comparison** (filtered to .so loading):

```
# @Native path — loads from .dart_tool/lib/ (build hook copy)
[pid 72205] .dart_tool/lib/libzenoh_dart.so  → SUCCESS
[pid 72205] .dart_tool/lib/libzenohc.so      → SUCCESS (via RUNPATH=$ORIGIN)

# DynamicLibrary.open() path — loads from native/ (via LD_LIBRARY_PATH)
72987 dart-sdk/bin/libzenoh_dart.so           → ENOENT (searched first)
72987 native/linux/x86_64/libzenoh_dart.so    → SUCCESS (via LD_LIBRARY_PATH)
72987 native/linux/x86_64/libzenohc.so        → SUCCESS (via LD_LIBRARY_PATH)
```

### Revised Root Cause

The crash is caused by **`@Native`'s library loading mechanism** in the Dart VM.
The exact mechanism is not fully understood, but the `NoActiveIsolateScope`
(thread-isolate detachment during dlopen) and/or the lazy per-symbol resolution
via `FfiResolve` are the likely culprits. The crash manifests when tokio's I/O
event driver processes an incoming TCP connection on a worker thread.

**Why it works with `DynamicLibrary.open()`:** The library is loaded eagerly
on the main isolate thread, all symbols resolved upfront. No thread-isolate
detachment during loading. Tokio's runtime is initialized in a "normal" thread
context.

**Why it works in-process:** Single dlopen call, one tokio runtime instance
shared by both sessions. No cross-process TCP events to trigger the crash.

**Why it works with native zenoh-c processes:** The native C executable loads
libzenohc.so via the normal ELF loader at startup. Only the Dart side uses
dlopen.

### Proposed Fix (Revised)

> **NOTE (2026-03-11):** The hybrid approach below was attempted (commit
> `a9e6625`) and **failed**. `@Native`'s `NoActiveIsolateScope` taints the
> dlopen handle even when pre-loaded. The actual fix reverted `@Native` entirely
> to class-based `ZenohDartBindings(DynamicLibrary)` (commit `93e29e5`). See
> `docs/reviews/interprocess-crash-fix-review.md` for details.

**Hybrid approach (failed):** Keep `@Native` annotations for bindings (needed for
pub.dev distribution and build hook integration), but pre-load both libraries
eagerly via `DynamicLibrary.open()` in `ensureInitialized()` before any
`@Native` call triggers lazy resolution.

When `@Native` later calls `dlopen()` on the same library path, the OS linker
returns the already-loaded handle (refcount increment). This effectively makes
the loading behave like `DynamicLibrary.open()` while keeping `@Native` for
symbol resolution.

See `docs/design/fix-rtld-local-interprocess-crash.md` for the original
design specification.

### Relevant Upstream Issues

- https://github.com/dart-lang/sdk/issues/50105 — Request for RTLD_GLOBAL
  support in DynamicLibrary.open() (OPEN)
- https://github.com/rust-lang/rust/issues/54291 — Rust TLS + dlopen
- https://github.com/rust-lang/rust/issues/91979 — Segfault when thread using
  dynamically loaded Rust library exits

### Downstream Impact (After Fix)

1. **zenoh-counter-dart** — Remove all LD_LIBRARY_PATH from docs
2. **zenoh-counter-cpp** — Simplify interop tests
3. **All future consumers** — Benefit automatically
