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

// ---------------------------------------------------------------------------
// KeyExpr
// ---------------------------------------------------------------------------

/// Returns the size of z_view_keyexpr_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_view_keyexpr_sizeof(void);

/// Creates a view key expression from a null-terminated string.
///
/// The string must remain valid for the lifetime of the view.
///
/// @param ke    Pointer to an uninitialized z_view_keyexpr_t.
/// @param expr  Null-terminated key expression string.
/// @return 0 on success, Z_EINVAL (-1) if the expression is invalid.
FFI_PLUGIN_EXPORT int zd_view_keyexpr_from_str(z_view_keyexpr_t* ke,
                                               const char* expr);

/// Obtains a const loaned reference to the key expression.
///
/// @param ke  Pointer to a valid z_view_keyexpr_t.
/// @return Const pointer to the loaned key expression.
FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_view_keyexpr_loan(
    const z_view_keyexpr_t* ke);

/// Converts a loaned key expression to a view string.
///
/// The output view string borrows from the key expression and must not
/// outlive it. Returns void -- always succeeds on a valid loaned keyexpr.
///
/// @param ke   Const pointer to a loaned key expression.
/// @param out  Pointer to an uninitialized z_view_string_t to receive the result.
FFI_PLUGIN_EXPORT void zd_keyexpr_as_view_string(
    const z_loaned_keyexpr_t* ke, z_view_string_t* out);

// ---------------------------------------------------------------------------
// Bytes
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_bytes_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_bytes_sizeof(void);

/// Copies a null-terminated string into owned bytes.
///
/// @param bytes  Pointer to an uninitialized z_owned_bytes_t.
/// @param str    Null-terminated string to copy.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_bytes_copy_from_str(z_owned_bytes_t* bytes,
                                             const char* str);

/// Copies a buffer into owned bytes.
///
/// @param bytes  Pointer to an uninitialized z_owned_bytes_t.
/// @param data   Pointer to the buffer data.
/// @param len    Length of the buffer in bytes.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_bytes_copy_from_buf(z_owned_bytes_t* bytes,
                                             const uint8_t* data, size_t len);

/// Converts loaned bytes to an owned string.
///
/// @param bytes  Const pointer to a loaned bytes reference.
/// @param out    Pointer to an uninitialized z_owned_string_t to receive the result.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_bytes_to_string(const z_loaned_bytes_t* bytes,
                                         z_owned_string_t* out);

/// Obtains a const loaned reference to the bytes.
///
/// @param bytes  Pointer to a valid z_owned_bytes_t.
/// @return Const pointer to the loaned bytes.
FFI_PLUGIN_EXPORT const z_loaned_bytes_t* zd_bytes_loan(
    const z_owned_bytes_t* bytes);

/// Drops (frees) owned bytes.
///
/// After this call the owned bytes are in gravestone state.
/// A second drop is a safe no-op.
///
/// @param bytes  Pointer to a z_owned_bytes_t to drop.
FFI_PLUGIN_EXPORT void zd_bytes_drop(z_owned_bytes_t* bytes);

// ---------------------------------------------------------------------------
// Owned String
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_string_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_string_sizeof(void);

/// Obtains a const loaned reference to the owned string.
///
/// @param str  Pointer to a valid z_owned_string_t.
/// @return Const pointer to the loaned string.
FFI_PLUGIN_EXPORT const z_loaned_string_t* zd_string_loan(
    const z_owned_string_t* str);

/// Returns a pointer to the data of a loaned string.
///
/// The returned pointer is NOT guaranteed to be null-terminated.
///
/// @param str  Const pointer to a loaned string.
/// @return Pointer to the string data.
FFI_PLUGIN_EXPORT const char* zd_string_data(const z_loaned_string_t* str);

/// Returns the length of a loaned string (in bytes, NOT including any terminator).
///
/// @param str  Const pointer to a loaned string.
/// @return Length of the string data in bytes.
FFI_PLUGIN_EXPORT size_t zd_string_len(const z_loaned_string_t* str);

/// Drops (frees) an owned string.
///
/// After this call the owned string is in gravestone state.
/// A second drop is a safe no-op.
///
/// @param str  Pointer to a z_owned_string_t to drop.
FFI_PLUGIN_EXPORT void zd_string_drop(z_owned_string_t* str);

// ---------------------------------------------------------------------------
// View String utilities
// ---------------------------------------------------------------------------

/// Returns the size of z_view_string_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_view_string_sizeof(void);

/// Returns a pointer to the data of a view string.
///
/// Internally loans the view string and calls z_string_data on the loaned ref.
/// The returned pointer is NOT guaranteed to be null-terminated.
///
/// @param str  Pointer to a valid z_view_string_t.
/// @return Pointer to the string data.
FFI_PLUGIN_EXPORT const char* zd_view_string_data(const z_view_string_t* str);

/// Returns the length of a view string (in bytes, NOT including any terminator).
///
/// Internally loans the view string and calls z_string_len on the loaned ref.
///
/// @param str  Pointer to a valid z_view_string_t.
/// @return Length of the string data in bytes.
FFI_PLUGIN_EXPORT size_t zd_view_string_len(const z_view_string_t* str);

#endif // ZENOH_DART_H
