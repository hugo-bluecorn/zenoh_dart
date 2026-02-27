#ifndef ZENOH_DART_H
#define ZENOH_DART_H

#include <stdint.h>
#include <zenoh.h>

// FFI_PLUGIN_EXPORT: marks symbols for visibility from Dart FFI.
#if defined(_WIN32) || defined(__CYGWIN__)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

// ---------------------------------------------------------------------------
// Dart API initialization
// ---------------------------------------------------------------------------

/// Initializes the Dart native API for dynamic linking.
///
/// Must be called before any other zenoh_dart functions that use
/// Dart native ports. Pass `NativeApi.initializeApiDLData` from Dart.
///
/// Returns 0 on success.
FFI_PLUGIN_EXPORT intptr_t zd_init_dart_api_dl(void* data);

/// Initializes the zenoh logger from the RUST_LOG environment variable,
/// falling back to the provided filter string if RUST_LOG is not set.
///
/// @param fallback_filter  Filter string (e.g., "error", "info", "debug").
FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter);

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_config_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_config_sizeof(void);

/// Creates a default configuration.
///
/// @param config  Pointer to an uninitialized z_owned_config_t.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_config_default(z_owned_config_t* config);

/// Inserts a JSON5 value into the configuration at the given key path.
///
/// Takes a mutable owned config pointer. Internally obtains a mutable loan
/// via z_config_loan_mut() before calling zc_config_insert_json5().
///
/// @param config  Pointer to a valid z_owned_config_t.
/// @param key     Configuration key path (e.g., "mode").
/// @param value   JSON5 value string (e.g., "\"peer\"").
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_config_insert_json5(
    z_owned_config_t* config, const char* key, const char* value);

/// Obtains a const loaned reference to the configuration.
///
/// @param config  Pointer to a valid z_owned_config_t.
/// @return Const pointer to the loaned config.
FFI_PLUGIN_EXPORT const z_loaned_config_t* zd_config_loan(
    const z_owned_config_t* config);

/// Drops (frees) the configuration.
///
/// After this call the owned config is in gravestone state.
/// A second drop is a safe no-op.
///
/// @param config  Pointer to a z_owned_config_t to drop.
FFI_PLUGIN_EXPORT void zd_config_drop(z_owned_config_t* config);

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_session_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void);

/// Opens a Zenoh session with the given configuration.
///
/// @param session  Pointer to an uninitialized z_owned_session_t.
/// @param config   Pointer to a z_owned_config_t (consumed by z_open).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_open_session(z_owned_session_t* session,
                                      z_owned_config_t* config);

/// Obtains a const loaned reference to the session.
///
/// @param session  Pointer to a valid z_owned_session_t.
/// @return Const pointer to the loaned session.
FFI_PLUGIN_EXPORT const z_loaned_session_t* zd_session_loan(
    const z_owned_session_t* session);

/// Gracefully closes and drops the session.
///
/// Calls z_close for graceful shutdown, then z_session_drop to release
/// resources. After this call the owned session is in gravestone state.
///
/// @param session  Pointer to a z_owned_session_t to close and drop.
FFI_PLUGIN_EXPORT void zd_close_session(z_owned_session_t* session);

#endif // ZENOH_DART_H
