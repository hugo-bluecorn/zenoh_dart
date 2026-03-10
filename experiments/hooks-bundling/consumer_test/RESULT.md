# Consumer Test Result

## Setup
- Created via: `fvm dart create -t console consumer_test`
- Dependency: `exp_hooks_prebuilt_native` (path)
- Platform: Linux x86_64
- Dart SDK: 3.11.1 (stable)
- FVM Flutter: 3.41.4 (stable)

## Verification

### dart run (no LD_LIBRARY_PATH)
- [x] Pass
- Exit code: 0
- Output:
```
Running build hooks...Running build hooks...initZenohDart() returned: true
```

### dart analyze
- [x] Pass

### Build hook fires transitively
- [x] Yes
- Evidence: "Running build hooks..." appears in output when running from the consumer project (not from within the dependency package)

## Conclusion

The hooks mechanism works from an external consumer project. When `exp_hooks_prebuilt_native` is added as a path dependency to a standalone `dart create -t console` project:

1. `fvm dart pub get` resolves the dependency and its transitive hook dependencies (`hooks`, `code_assets`)
2. `fvm dart run` triggers the dependency's build hook transitively
3. `@Native` annotation resolution finds the hook-bundled `libzenoh_dart.so` from the consumer's context
4. DT_NEEDED resolution finds co-located `libzenohc.so` via RUNPATH=$ORIGIN
5. Both `zd_init_dart_api_dl` and `zd_init_log` FFI calls succeed
6. No `LD_LIBRARY_PATH` environment variable needed

This closes the methodology gap from experiments A1-B2: the hook mechanism is not limited to in-package execution. External consumers get the same transparent native library resolution.
