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

// ---------------------------------------------------------------------------
// Put / Delete
// ---------------------------------------------------------------------------

/// Publishes data on the given key expression.
///
/// The payload is consumed (moved) by this call -- the caller must not
/// use the owned bytes after calling zd_put.
///
/// @param session  Const pointer to a loaned session.
/// @param keyexpr  Const pointer to a loaned key expression.
/// @param payload  Pointer to an owned bytes (consumed via z_bytes_move).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload);

/// Deletes a resource on the given key expression.
///
/// @param session  Const pointer to a loaned session.
/// @param keyexpr  Const pointer to a loaned key expression.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_delete(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr);

// ---------------------------------------------------------------------------
// Subscriber
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_subscriber_t in bytes.
///
/// Used by Dart to allocate the correct amount of native memory
/// for opaque zenoh types.
FFI_PLUGIN_EXPORT size_t zd_subscriber_sizeof(void);

/// Declares a subscriber on the given key expression.
///
/// Samples are posted to the Dart isolate via `Dart_PostCObject_DL` on
/// the given native port. Each sample is sent as a `Dart_CObject` array
/// of 4 elements: [keyexpr(string), payload(Uint8List), kind(int64),
/// attachment(null or Uint8List)].
///
/// @param session     Const pointer to a loaned session.
/// @param subscriber  Pointer to an uninitialized z_owned_subscriber_t.
/// @param keyexpr     Const pointer to a loaned key expression.
/// @param dart_port   The Dart native port to post samples to.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_declare_subscriber(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port);

/// Drops (undeclares and frees) a subscriber.
///
/// After this call the owned subscriber is in gravestone state.
/// A second drop is a safe no-op.
///
/// @param subscriber  Pointer to a z_owned_subscriber_t to drop.
FFI_PLUGIN_EXPORT void zd_subscriber_drop(z_owned_subscriber_t* subscriber);

// ---------------------------------------------------------------------------
// Publisher
// ---------------------------------------------------------------------------

/// Returns the size of z_owned_publisher_t in bytes.
FFI_PLUGIN_EXPORT size_t zd_publisher_sizeof(void);

/// Declares a publisher on the given key expression.
///
/// @param session             Const pointer to a loaned session.
/// @param publisher           Pointer to an uninitialized z_owned_publisher_t.
/// @param keyexpr             Const pointer to a loaned key expression.
/// @param encoding            MIME type string for default encoding (NULL = default).
/// @param congestion_control  Congestion control strategy (-1 = default/block).
/// @param priority            Message priority (-1 = default/data=5).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_declare_publisher(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    const char* encoding,
    int congestion_control,
    int priority);

/// Obtains a const loaned reference to the publisher.
FFI_PLUGIN_EXPORT const z_loaned_publisher_t* zd_publisher_loan(
    const z_owned_publisher_t* publisher);

/// Drops (undeclares and frees) a publisher.
FFI_PLUGIN_EXPORT void zd_publisher_drop(z_owned_publisher_t* publisher);

/// Publishes data through the publisher.
///
/// @param publisher   Const pointer to a loaned publisher.
/// @param payload     Pointer to owned bytes (consumed via z_bytes_move).
/// @param encoding    MIME type string for per-put encoding override (NULL = publisher default).
/// @param attachment  Pointer to owned bytes for attachment (consumed if non-NULL, NULL = no attachment).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_publisher_put(
    const z_loaned_publisher_t* publisher,
    z_owned_bytes_t* payload,
    const char* encoding,
    z_owned_bytes_t* attachment);

/// Sends a DELETE through the publisher.
FFI_PLUGIN_EXPORT int zd_publisher_delete(
    const z_loaned_publisher_t* publisher);

/// Returns the key expression of a publisher.
FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_publisher_keyexpr(
    const z_loaned_publisher_t* publisher);

/// Declares a background matching listener on the publisher.
///
/// Matching status changes are posted to the Dart isolate via the given
/// native port as Int64 values (1 = matching, 0 = not matching).
///
/// @param publisher  Const pointer to a loaned publisher.
/// @param dart_port  The Dart native port to post matching status to.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_publisher_declare_background_matching_listener(
    const z_loaned_publisher_t* publisher,
    int64_t dart_port);

/// Gets the current matching status of a publisher.
///
/// @param publisher  Const pointer to a loaned publisher.
/// @param matching   Out parameter: filled with 0 (no match) or 1 (match).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_publisher_get_matching_status(
    const z_loaned_publisher_t* publisher,
    int* matching);

// ---------------------------------------------------------------------------
// Shared Memory (SHM)
// ---------------------------------------------------------------------------
#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)

/// Returns the size of z_owned_shm_provider_t in bytes.
FFI_PLUGIN_EXPORT size_t zd_shm_provider_sizeof(void);

/// Creates a default SHM provider with the given total size.
///
/// @param provider  Pointer to an uninitialized z_owned_shm_provider_t.
/// @param total_size  Total size of the SHM pool in bytes.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_shm_provider_new(z_owned_shm_provider_t* provider,
                                          size_t total_size);

/// Obtains a const loaned reference to the SHM provider.
FFI_PLUGIN_EXPORT const z_loaned_shm_provider_t* zd_shm_provider_loan(
    const z_owned_shm_provider_t* provider);

/// Drops (frees) the SHM provider.
FFI_PLUGIN_EXPORT void zd_shm_provider_drop(z_owned_shm_provider_t* provider);

/// Returns the available (free) bytes in the SHM provider.
FFI_PLUGIN_EXPORT size_t zd_shm_provider_available(
    const z_loaned_shm_provider_t* provider);

/// Returns the size of z_owned_shm_mut_t in bytes.
FFI_PLUGIN_EXPORT size_t zd_shm_mut_sizeof(void);

/// Allocates a mutable SHM buffer from the provider.
///
/// @param provider  Const pointer to a loaned SHM provider.
/// @param buf       Pointer to an uninitialized z_owned_shm_mut_t.
/// @param size      Size of the buffer to allocate.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_shm_provider_alloc(
    const z_loaned_shm_provider_t* provider,
    z_owned_shm_mut_t* buf,
    size_t size);

/// Allocates a mutable SHM buffer with GC + defrag + blocking.
///
/// @param provider  Const pointer to a loaned SHM provider.
/// @param buf       Pointer to an uninitialized z_owned_shm_mut_t.
/// @param size      Size of the buffer to allocate.
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_shm_provider_alloc_gc_defrag_blocking(
    const z_loaned_shm_provider_t* provider,
    z_owned_shm_mut_t* buf,
    size_t size);

/// Obtains a mutable loaned reference to the SHM buffer.
FFI_PLUGIN_EXPORT z_loaned_shm_mut_t* zd_shm_mut_loan_mut(
    z_owned_shm_mut_t* buf);

/// Returns a mutable pointer to the SHM buffer data.
FFI_PLUGIN_EXPORT uint8_t* zd_shm_mut_data_mut(z_loaned_shm_mut_t* buf);

/// Returns the length of the SHM buffer.
FFI_PLUGIN_EXPORT size_t zd_shm_mut_len(const z_loaned_shm_mut_t* buf);

/// Converts a mutable SHM buffer into owned bytes (consuming the buffer).
///
/// @param bytes  Pointer to an uninitialized z_owned_bytes_t.
/// @param buf    Pointer to a z_owned_shm_mut_t (consumed).
/// @return 0 on success, negative on failure.
FFI_PLUGIN_EXPORT int zd_bytes_from_shm_mut(z_owned_bytes_t* bytes,
                                            z_owned_shm_mut_t* buf);

/// Drops (frees) a mutable SHM buffer.
FFI_PLUGIN_EXPORT void zd_shm_mut_drop(z_owned_shm_mut_t* buf);

#endif // Z_FEATURE_SHARED_MEMORY && Z_FEATURE_UNSTABLE_API

#endif // ZENOH_DART_H
