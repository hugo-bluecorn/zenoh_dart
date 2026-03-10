# Consumer Test: External App Verifies Hook-Bundled Dependencies

> **Date**: 2026-03-10
> **Author**: CA (Architect)
> **Status**: Spec complete, ready for CI
> **Location**: `experiments/hooks-bundling/consumer-test/`
> **Branch**: `experiment/consumer-test`
> **Parent**: `experiments/hooks-bundling/design.md`

## Objective

Prove that the winning experiment (A2: prebuilt + @Native) works when
consumed as a **dependency** from an external Dart project — not just when
running tests from within the experiment package itself.

This closes the methodology gap: experiments A1–B2 tested the hooks
mechanism from within each package. A real user would `dart create` a
project, add `zenoh` as a dependency, and run their code. The hook must
fire transitively and `@Native` assets must resolve from the consumer's
context.

## Why Only A2

The 2x2 matrix conclusively proved that `@Native` is the sole determinant
of success. The build strategy (prebuilt vs CBuilder) is irrelevant:

| | DynamicLibrary.open() | @Native |
|---|---|---|
| **Prebuilt** | A1: NEGATIVE | A2: POSITIVE |
| **CBuilder** | B1: NEGATIVE | B2: POSITIVE |

Testing A2 as a dependency is sufficient because:
- If A2 works as a dependency, the hook + @Native mechanism is proven
  end-to-end (the same mechanism that makes B2 work)
- If A2 fails as a dependency, the entire hooks approach has a gap that
  affects B2 equally

## Procedure

### Step 1: Create the project with `dart create`

```bash
cd experiments/hooks-bundling/
fvm dart create -t console consumer_test
```

This mirrors what a real user would do. The generated scaffold includes
`pubspec.yaml`, `bin/consumer_test.dart`, `analysis_options.yaml`, etc.

### Step 2: Add path dependency on A2

Edit `consumer_test/pubspec.yaml` to add:

```yaml
dependencies:
  exp_hooks_prebuilt_native:
    path: ../../../packages/exp_hooks_prebuilt_native
```

Then run:

```bash
cd consumer_test && fvm dart pub get
```

### Step 3: Replace bin/consumer_test.dart

```dart
import 'package:exp_hooks_prebuilt_native/exp_hooks_prebuilt_native.dart';

void main() {
  try {
    final result = initZenohDart();
    print('initZenohDart() returned: $result');
  } catch (e) {
    print('initZenohDart() failed: $e');
    // ignore: avoid_catches_without_on_clauses
  }
}
```

### Step 4: Run without LD_LIBRARY_PATH

```bash
cd experiments/hooks-bundling/consumer-test && fvm dart run bin/consumer_test.dart
```

**Expected output:**
```
Running build hooks...Running build hooks...initZenohDart() returned: true
```

Exit code 0. No `LD_LIBRARY_PATH` needed.

### Step 5: Run dart analyze

```bash
fvm dart analyze experiments/hooks-bundling/consumer-test
```

Expected: no issues.

## Acceptance Criteria

1. Project created via `fvm dart create -t console consumer_test`
2. Depends on `exp_hooks_prebuilt_native` via path dependency
3. `fvm dart run bin/consumer_test.dart` succeeds **without
   LD_LIBRARY_PATH**
4. Output contains `initZenohDart() returned: true`
5. Exit code is 0
6. `fvm dart analyze` passes
7. Build hook evidence visible in output ("Running build hooks...")
8. Result (pass or fail) documented in
   `experiments/hooks-bundling/consumer-test/RESULT.md`

## RESULT.md Template

```markdown
# Consumer Test Result

## Setup
- Created via: `fvm dart create -t console consumer_test`
- Dependency: `exp_hooks_prebuilt_native` (path)
- Platform: Linux x86_64
- Dart SDK: (fill in)
- FVM Flutter: (fill in)

## Verification

### dart run (no LD_LIBRARY_PATH)
- [ ] Pass / Fail
- Exit code:
- Output:

### dart analyze
- [ ] Pass / Fail

### Build hook fires transitively
- [ ] Yes / No
- Evidence:

## Conclusion
(Does the hooks mechanism work from an external consumer project?)
```

## What This Does NOT Test

- `dart test` from the consumer (no test file — just `dart run`)
- Flutter consumer (`flutter create` + dependency)
- pub.dev resolution (path dependency only)
- Multiple packages depending on the same hooked package
- Android/macOS/Windows

## Commit & PR

CI should:
1. Create branch `experiment/consumer-test`
2. Commit the `dart create` output + modifications + `RESULT.md`
3. Push and create PR against main
4. CA merges after verification
