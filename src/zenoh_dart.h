#ifndef ZENOH_DART_H
#define ZENOH_DART_H

// FFI_PLUGIN_EXPORT: marks symbols for visibility from Dart FFI.
#if defined(_WIN32) || defined(__CYGWIN__)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

// C shim functions are added in Phase 0+ via TDD.
// Each function is prefixed with zd_ to avoid collisions with zenoh-c.

#endif // ZENOH_DART_H
