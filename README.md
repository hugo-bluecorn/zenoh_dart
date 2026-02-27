# zenoh-dart

Dart bindings for the [Zenoh](https://zenoh.io/) pub/sub/query protocol via FFI.

## Packages

| Package | Description |
|---------|-------------|
| [`zenoh`](packages/zenoh/) | Pure Dart FFI bindings for zenoh-c |

## Development

Requires [FVM](https://fvm.app/) for Flutter/Dart SDK management.

```bash
# Install dependencies
fvm dart pub get

# Bootstrap Melos workspace
fvm dart run melos bootstrap

# Run tests
cd packages/zenoh && fvm dart test

# Analyze
fvm dart analyze packages/zenoh
```
