#include "zenoh_dart.h"
#include "dart/dart_api_dl.h"

#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// Dart API initialization
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT intptr_t zd_init_dart_api_dl(void* data) {
  return Dart_InitializeApiDL(data);
}

FFI_PLUGIN_EXPORT void zd_init_log(const char* fallback_filter) {
  zc_init_log_from_env_or(fallback_filter);
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_config_sizeof(void) {
  return sizeof(z_owned_config_t);
}

FFI_PLUGIN_EXPORT int zd_config_default(z_owned_config_t* config) {
  return z_config_default(config);
}

FFI_PLUGIN_EXPORT int zd_config_insert_json5(
    z_owned_config_t* config, const char* key, const char* value) {
  z_loaned_config_t* loaned = z_config_loan_mut(config);
  return zc_config_insert_json5(loaned, key, value);
}

FFI_PLUGIN_EXPORT const z_loaned_config_t* zd_config_loan(
    const z_owned_config_t* config) {
  return z_config_loan(config);
}

FFI_PLUGIN_EXPORT void zd_config_drop(z_owned_config_t* config) {
  z_config_drop(z_config_move(config));
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_session_sizeof(void) {
  return sizeof(z_owned_session_t);
}

FFI_PLUGIN_EXPORT int zd_open_session(z_owned_session_t* session,
                                      z_owned_config_t* config) {
  return z_open(session, z_config_move(config), NULL);
}

FFI_PLUGIN_EXPORT const z_loaned_session_t* zd_session_loan(
    const z_owned_session_t* session) {
  return z_session_loan(session);
}

FFI_PLUGIN_EXPORT void zd_close_session(z_owned_session_t* session) {
  z_close(z_session_loan_mut(session), NULL);
  z_session_drop(z_session_move(session));
}

// ---------------------------------------------------------------------------
// Bytes
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_bytes_sizeof(void) {
  return sizeof(z_owned_bytes_t);
}

FFI_PLUGIN_EXPORT int zd_bytes_copy_from_str(z_owned_bytes_t* bytes,
                                             const char* str) {
  return z_bytes_copy_from_str(bytes, str);
}

FFI_PLUGIN_EXPORT int zd_bytes_copy_from_buf(z_owned_bytes_t* bytes,
                                             const uint8_t* data, size_t len) {
  return z_bytes_copy_from_buf(bytes, data, len);
}

FFI_PLUGIN_EXPORT int zd_bytes_to_string(const z_loaned_bytes_t* bytes,
                                         z_owned_string_t* out) {
  return z_bytes_to_string(bytes, out);
}

FFI_PLUGIN_EXPORT const z_loaned_bytes_t* zd_bytes_loan(
    const z_owned_bytes_t* bytes) {
  return z_bytes_loan(bytes);
}

FFI_PLUGIN_EXPORT void zd_bytes_drop(z_owned_bytes_t* bytes) {
  z_bytes_drop(z_bytes_move(bytes));
}

// ---------------------------------------------------------------------------
// Owned String
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_string_sizeof(void) {
  return sizeof(z_owned_string_t);
}

FFI_PLUGIN_EXPORT const z_loaned_string_t* zd_string_loan(
    const z_owned_string_t* str) {
  return z_string_loan(str);
}

FFI_PLUGIN_EXPORT const char* zd_string_data(const z_loaned_string_t* str) {
  return z_string_data(str);
}

FFI_PLUGIN_EXPORT size_t zd_string_len(const z_loaned_string_t* str) {
  return z_string_len(str);
}

FFI_PLUGIN_EXPORT void zd_string_drop(z_owned_string_t* str) {
  z_string_drop(z_string_move(str));
}

// ---------------------------------------------------------------------------
// KeyExpr
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_view_keyexpr_sizeof(void) {
  return sizeof(z_view_keyexpr_t);
}

FFI_PLUGIN_EXPORT int zd_view_keyexpr_from_str(z_view_keyexpr_t* ke,
                                               const char* expr) {
  return z_view_keyexpr_from_str(ke, expr);
}

FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_view_keyexpr_loan(
    const z_view_keyexpr_t* ke) {
  return z_view_keyexpr_loan(ke);
}

FFI_PLUGIN_EXPORT void zd_keyexpr_as_view_string(
    const z_loaned_keyexpr_t* ke, z_view_string_t* out) {
  z_keyexpr_as_view_string(ke, out);
}

// ---------------------------------------------------------------------------
// View String utilities
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_view_string_sizeof(void) {
  return sizeof(z_view_string_t);
}

FFI_PLUGIN_EXPORT const char* zd_view_string_data(const z_view_string_t* str) {
  const z_loaned_string_t* loaned = z_view_string_loan(str);
  return z_string_data(loaned);
}

FFI_PLUGIN_EXPORT size_t zd_view_string_len(const z_view_string_t* str) {
  const z_loaned_string_t* loaned = z_view_string_loan(str);
  return z_string_len(loaned);
}

// ---------------------------------------------------------------------------
// Put / Delete
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT int zd_put(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr,
    z_owned_bytes_t* payload) {
  z_put_options_t opts;
  z_put_options_default(&opts);
  return z_put(session, keyexpr, z_bytes_move(payload), &opts);
}

FFI_PLUGIN_EXPORT int zd_delete(
    const z_loaned_session_t* session,
    const z_loaned_keyexpr_t* keyexpr) {
  z_delete_options_t opts;
  z_delete_options_default(&opts);
  return z_delete(session, keyexpr, &opts);
}

// ---------------------------------------------------------------------------
// Subscriber
// ---------------------------------------------------------------------------

/// Context struct passed to the closure callbacks.
typedef struct {
  Dart_Port_DL dart_port;
} zd_subscriber_context_t;

/// Sample callback: extracts fields and posts to Dart via native port.
static void _zd_sample_callback(z_loaned_sample_t* sample, void* context) {
  zd_subscriber_context_t* ctx = (zd_subscriber_context_t*)context;

  // 1. Key expression as string
  z_view_string_t key_view;
  z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_view);
  const z_loaned_string_t* key_loaned = z_view_string_loan(&key_view);
  size_t key_len = z_string_len(key_loaned);
  const char* key_data = z_string_data(key_loaned);

  // 2. Payload as bytes
  const z_loaned_bytes_t* payload_loaned = z_sample_payload(sample);
  z_owned_string_t payload_str;
  z_bytes_to_string(payload_loaned, &payload_str);
  const z_loaned_string_t* payload_str_loaned = z_string_loan(&payload_str);
  size_t payload_len = z_string_len(payload_str_loaned);
  const char* payload_data = z_string_data(payload_str_loaned);

  // 3. Kind as int
  z_sample_kind_t kind = z_sample_kind(sample);

  // 4. Attachment (nullable)
  const z_loaned_bytes_t* attachment = z_sample_attachment(sample);

  // 5. Encoding as string
  const z_loaned_encoding_t* encoding = z_sample_encoding(sample);
  z_owned_string_t encoding_str;
  z_encoding_to_string(encoding, &encoding_str);
  const z_loaned_string_t* enc_loaned = z_string_loan(&encoding_str);
  size_t enc_len = z_string_len(enc_loaned);
  const char* enc_data = z_string_data(enc_loaned);

  // Build Dart_CObject array: [keyexpr, payload, kind, attachment, encoding]
  Dart_CObject c_keyexpr;
  c_keyexpr.type = Dart_CObject_kString;
  // z_string_data may not be null-terminated, so copy to a buffer
  char* key_buf = (char*)malloc(key_len + 1);
  memcpy(key_buf, key_data, key_len);
  key_buf[key_len] = '\0';
  c_keyexpr.value.as_string = key_buf;

  Dart_CObject c_payload;
  c_payload.type = Dart_CObject_kTypedData;
  c_payload.value.as_typed_data.type = Dart_TypedData_kUint8;
  c_payload.value.as_typed_data.length = (intptr_t)payload_len;
  c_payload.value.as_typed_data.values = (uint8_t*)payload_data;

  Dart_CObject c_kind;
  c_kind.type = Dart_CObject_kInt64;
  c_kind.value.as_int64 = (int64_t)kind;

  Dart_CObject c_attachment;
  z_owned_string_t attachment_str;
  bool has_attachment = (attachment != NULL);
  if (has_attachment) {
    z_bytes_to_string(attachment, &attachment_str);
    const z_loaned_string_t* att_loaned = z_string_loan(&attachment_str);
    c_attachment.type = Dart_CObject_kTypedData;
    c_attachment.value.as_typed_data.type = Dart_TypedData_kUint8;
    c_attachment.value.as_typed_data.length = (intptr_t)z_string_len(att_loaned);
    c_attachment.value.as_typed_data.values = (uint8_t*)z_string_data(att_loaned);
  } else {
    c_attachment.type = Dart_CObject_kNull;
  }

  Dart_CObject c_encoding;
  char* enc_buf = (char*)malloc(enc_len + 1);
  memcpy(enc_buf, enc_data, enc_len);
  enc_buf[enc_len] = '\0';
  c_encoding.type = Dart_CObject_kString;
  c_encoding.value.as_string = enc_buf;

  Dart_CObject* elements[5] = {&c_keyexpr, &c_payload, &c_kind, &c_attachment, &c_encoding};
  Dart_CObject c_array;
  c_array.type = Dart_CObject_kArray;
  c_array.value.as_array.length = 5;
  c_array.value.as_array.values = elements;

  Dart_PostCObject_DL(ctx->dart_port, &c_array);

  // Cleanup
  free(key_buf);
  free(enc_buf);
  z_string_drop(z_string_move(&payload_str));
  z_string_drop(z_string_move(&encoding_str));
  if (has_attachment) {
    z_string_drop(z_string_move(&attachment_str));
  }
}

/// Drop callback: frees the context struct.
static void _zd_sample_drop(void* context) {
  free(context);
}

FFI_PLUGIN_EXPORT size_t zd_subscriber_sizeof(void) {
  return sizeof(z_owned_subscriber_t);
}

FFI_PLUGIN_EXPORT int zd_declare_subscriber(
    const z_loaned_session_t* session,
    z_owned_subscriber_t* subscriber,
    const z_loaned_keyexpr_t* keyexpr,
    int64_t dart_port) {
  zd_subscriber_context_t* ctx =
      (zd_subscriber_context_t*)malloc(sizeof(zd_subscriber_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)dart_port;

  z_owned_closure_sample_t callback;
  z_closure_sample(&callback, _zd_sample_callback, _zd_sample_drop, ctx);

  int rc = z_declare_subscriber(
      session, subscriber, keyexpr,
      z_closure_sample_move(&callback), NULL);

  if (rc != 0) {
    // closure was not consumed on failure, drop it manually
    z_closure_sample_drop(z_closure_sample_move(&callback));
  }

  return rc;
}

FFI_PLUGIN_EXPORT void zd_subscriber_drop(z_owned_subscriber_t* subscriber) {
  z_subscriber_drop(z_subscriber_move(subscriber));
}

// ---------------------------------------------------------------------------
// Publisher
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_publisher_sizeof(void) {
  return sizeof(z_owned_publisher_t);
}

FFI_PLUGIN_EXPORT int zd_declare_publisher(
    const z_loaned_session_t* session,
    z_owned_publisher_t* publisher,
    const z_loaned_keyexpr_t* keyexpr,
    const char* encoding,
    int congestion_control,
    int priority) {
  z_publisher_options_t opts;
  z_publisher_options_default(&opts);

  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
  }
  if (congestion_control >= 0) {
    opts.congestion_control = (z_congestion_control_t)congestion_control;
  }
  if (priority >= 0) {
    opts.priority = (z_priority_t)priority;
  }

  return z_declare_publisher(session, publisher, keyexpr, &opts);
}

FFI_PLUGIN_EXPORT const z_loaned_publisher_t* zd_publisher_loan(
    const z_owned_publisher_t* publisher) {
  return z_publisher_loan(publisher);
}

FFI_PLUGIN_EXPORT void zd_publisher_drop(z_owned_publisher_t* publisher) {
  z_publisher_drop(z_publisher_move(publisher));
}

FFI_PLUGIN_EXPORT int zd_publisher_put(
    const z_loaned_publisher_t* publisher,
    z_owned_bytes_t* payload,
    const char* encoding,
    z_owned_bytes_t* attachment) {
  z_publisher_put_options_t opts;
  z_publisher_put_options_default(&opts);

  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
  }
  if (attachment != NULL) {
    opts.attachment = z_bytes_move(attachment);
  }

  return z_publisher_put(publisher, z_bytes_move(payload), &opts);
}

FFI_PLUGIN_EXPORT int zd_publisher_delete(
    const z_loaned_publisher_t* publisher) {
  z_publisher_delete_options_t opts;
  z_publisher_delete_options_default(&opts);
  return z_publisher_delete(publisher, &opts);
}

FFI_PLUGIN_EXPORT const z_loaned_keyexpr_t* zd_publisher_keyexpr(
    const z_loaned_publisher_t* publisher) {
  return z_publisher_keyexpr(publisher);
}

/// Context struct for matching status callback.
typedef struct {
  Dart_Port_DL dart_port;
} zd_matching_context_t;

/// Matching status callback: posts matching status to Dart.
static void _zd_matching_status_callback(
    const z_matching_status_t* status, void* context) {
  zd_matching_context_t* ctx = (zd_matching_context_t*)context;

  Dart_CObject c_matching;
  c_matching.type = Dart_CObject_kInt64;
  c_matching.value.as_int64 = status->matching ? 1 : 0;

  Dart_PostCObject_DL(ctx->dart_port, &c_matching);
}

/// Drop callback for matching status context.
static void _zd_matching_drop(void* context) {
  free(context);
}

FFI_PLUGIN_EXPORT int zd_publisher_declare_background_matching_listener(
    const z_loaned_publisher_t* publisher,
    int64_t dart_port) {
  zd_matching_context_t* ctx =
      (zd_matching_context_t*)malloc(sizeof(zd_matching_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)dart_port;

  z_owned_closure_matching_status_t callback;
  z_closure_matching_status(
      &callback, _zd_matching_status_callback, _zd_matching_drop, ctx);

  int rc = z_publisher_declare_background_matching_listener(
      publisher, z_closure_matching_status_move(&callback));

  if (rc != 0) {
    z_closure_matching_status_drop(z_closure_matching_status_move(&callback));
  }

  return rc;
}

FFI_PLUGIN_EXPORT int zd_publisher_get_matching_status(
    const z_loaned_publisher_t* publisher,
    int* matching) {
  z_matching_status_t status;
  int rc = z_publisher_get_matching_status(publisher, &status);
  if (rc == 0) {
    *matching = status.matching ? 1 : 0;
  }
  return rc;
}

// ---------------------------------------------------------------------------
// Info (Session identity)
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT void zd_info_zid(const z_loaned_session_t* session,
                                   uint8_t* out_id) {
  z_id_t zid = z_info_zid(session);
  memcpy(out_id, zid.id, 16);
}

FFI_PLUGIN_EXPORT void zd_id_to_string(const uint8_t* id,
                                       z_owned_string_t* out) {
  z_id_t zid;
  memcpy(zid.id, id, 16);
  z_id_to_string(&zid, out);
}

// ---------------------------------------------------------------------------
// Shared Memory (SHM)
// ---------------------------------------------------------------------------
#if defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API)

FFI_PLUGIN_EXPORT size_t zd_shm_provider_sizeof(void) {
  return sizeof(z_owned_shm_provider_t);
}

FFI_PLUGIN_EXPORT int zd_shm_provider_new(z_owned_shm_provider_t* provider,
                                          size_t total_size) {
  return z_shm_provider_default_new(provider, total_size);
}

FFI_PLUGIN_EXPORT const z_loaned_shm_provider_t* zd_shm_provider_loan(
    const z_owned_shm_provider_t* provider) {
  return z_shm_provider_loan(provider);
}

FFI_PLUGIN_EXPORT void zd_shm_provider_drop(z_owned_shm_provider_t* provider) {
  z_shm_provider_drop(z_shm_provider_move(provider));
}

FFI_PLUGIN_EXPORT size_t zd_shm_provider_available(
    const z_loaned_shm_provider_t* provider) {
  return z_shm_provider_available(provider);
}

FFI_PLUGIN_EXPORT size_t zd_shm_mut_sizeof(void) {
  return sizeof(z_owned_shm_mut_t);
}

FFI_PLUGIN_EXPORT int zd_shm_provider_alloc(
    const z_loaned_shm_provider_t* provider,
    z_owned_shm_mut_t* buf,
    size_t size) {
  z_buf_layout_alloc_result_t result;
  z_shm_provider_alloc(&result, provider, size);
  if (result.status == ZC_BUF_LAYOUT_ALLOC_STATUS_OK) {
    *buf = result.buf;
    return 0;
  }
  return -1;
}

FFI_PLUGIN_EXPORT int zd_shm_provider_alloc_gc_defrag_blocking(
    const z_loaned_shm_provider_t* provider,
    z_owned_shm_mut_t* buf,
    size_t size) {
  z_buf_layout_alloc_result_t result;
  z_shm_provider_alloc_gc_defrag_blocking(&result, provider, size);
  if (result.status == ZC_BUF_LAYOUT_ALLOC_STATUS_OK) {
    *buf = result.buf;
    return 0;
  }
  return -1;
}

FFI_PLUGIN_EXPORT z_loaned_shm_mut_t* zd_shm_mut_loan_mut(
    z_owned_shm_mut_t* buf) {
  return z_shm_mut_loan_mut(buf);
}

FFI_PLUGIN_EXPORT uint8_t* zd_shm_mut_data_mut(z_loaned_shm_mut_t* buf) {
  return z_shm_mut_data_mut(buf);
}

FFI_PLUGIN_EXPORT size_t zd_shm_mut_len(const z_loaned_shm_mut_t* buf) {
  return z_shm_mut_len(buf);
}

FFI_PLUGIN_EXPORT int zd_bytes_from_shm_mut(z_owned_bytes_t* bytes,
                                            z_owned_shm_mut_t* buf) {
  return z_bytes_from_shm_mut(bytes, z_shm_mut_move(buf));
}

FFI_PLUGIN_EXPORT void zd_shm_mut_drop(z_owned_shm_mut_t* buf) {
  z_shm_mut_drop(z_shm_mut_move(buf));
}

#endif // Z_FEATURE_SHARED_MEMORY && Z_FEATURE_UNSTABLE_API
