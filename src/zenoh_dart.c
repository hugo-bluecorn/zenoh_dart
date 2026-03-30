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

FFI_PLUGIN_EXPORT int32_t zd_bytes_len(const uint8_t* bytes) {
  const z_owned_bytes_t* owned = (const z_owned_bytes_t*)bytes;
  const z_loaned_bytes_t* loaned = z_bytes_loan(owned);
  return (int32_t)z_bytes_len(loaned);
}

FFI_PLUGIN_EXPORT int8_t zd_bytes_to_buf(const uint8_t* bytes,
                                          uint8_t* out, int32_t capacity) {
  const z_owned_bytes_t* owned = (const z_owned_bytes_t*)bytes;
  const z_loaned_bytes_t* loaned = z_bytes_loan(owned);
  z_bytes_reader_t reader = z_bytes_get_reader(loaned);
  z_bytes_reader_read(&reader, out, (size_t)capacity);
  return 0;
}

FFI_PLUGIN_EXPORT void zd_bytes_drop(z_owned_bytes_t* bytes) {
  z_bytes_drop(z_bytes_move(bytes));
}

FFI_PLUGIN_EXPORT int8_t zd_bytes_clone(uint8_t* dst, const uint8_t* src) {
  z_owned_bytes_t* dst_owned = (z_owned_bytes_t*)dst;
  const z_owned_bytes_t* src_owned = (const z_owned_bytes_t*)src;
  const z_loaned_bytes_t* loaned = z_bytes_loan(src_owned);
  z_bytes_clone(dst_owned, loaned);
  return 0;
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

/// Drop callback that posts a null sentinel before freeing.
/// Used by background subscribers to signal stream completion when the
/// session closes and the background subscriber is dropped by zenoh-c.
static void _zd_sample_drop_with_sentinel(void* context) {
  zd_subscriber_context_t* ctx = (zd_subscriber_context_t*)context;
  Dart_CObject null_obj;
  null_obj.type = Dart_CObject_kNull;
  Dart_PostCObject_DL(ctx->dart_port, &null_obj);
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

FFI_PLUGIN_EXPORT int8_t zd_declare_background_subscriber(
    const z_loaned_session_t* session,
    const char* key_expr,
    int64_t dart_port) {
  // Validate key expression
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  zd_subscriber_context_t* ctx =
      (zd_subscriber_context_t*)malloc(sizeof(zd_subscriber_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)dart_port;

  z_owned_closure_sample_t callback;
  z_closure_sample(&callback, _zd_sample_callback,
                   _zd_sample_drop_with_sentinel, ctx);

  int rc = z_declare_background_subscriber(
      session, z_view_keyexpr_loan(&ke),
      z_closure_sample_move(&callback), NULL);

  if (rc != 0) {
    z_closure_sample_drop(z_closure_sample_move(&callback));
  }

  return rc;
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
    int priority,
    int8_t is_express) {
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
  if (is_express >= 0) {
    opts.is_express = (bool)is_express;
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

// Context for ZID collection closure
typedef struct {
  uint8_t* out_ids;
  int max_count;
  int count;
} zd_zid_collect_context_t;

// Callback that copies each z_id_t into the buffer
static void _zd_zid_collect_callback(const z_id_t* id, void* context) {
  zd_zid_collect_context_t* ctx = (zd_zid_collect_context_t*)context;
  if (ctx->count < ctx->max_count) {
    memcpy(ctx->out_ids + ctx->count * 16, id->id, 16);
    ctx->count++;
  }
}

FFI_PLUGIN_EXPORT int zd_info_routers_zid(const z_loaned_session_t* session,
                                          uint8_t* out_ids, int max_count) {
  zd_zid_collect_context_t ctx = {out_ids, max_count, 0};
  z_owned_closure_zid_t closure;
  z_closure_zid(&closure, _zd_zid_collect_callback, NULL, &ctx);
  z_info_routers_zid(session, z_closure_zid_move(&closure));
  return ctx.count;
}

FFI_PLUGIN_EXPORT int zd_info_peers_zid(const z_loaned_session_t* session,
                                        uint8_t* out_ids, int max_count) {
  zd_zid_collect_context_t ctx = {out_ids, max_count, 0};
  z_owned_closure_zid_t closure;
  z_closure_zid(&closure, _zd_zid_collect_callback, NULL, &ctx);
  z_info_peers_zid(session, z_closure_zid_move(&closure));
  return ctx.count;
}

// ---------------------------------------------------------------------------
// Scout
// ---------------------------------------------------------------------------

/// Context struct for scout hello callback.
typedef struct {
  Dart_Port_DL dart_port;
} zd_scout_context_t;

/// Hello callback: extracts fields and posts to Dart via native port.
static void _zd_scout_hello_callback(z_loaned_hello_t* hello, void* context) {
  zd_scout_context_t* ctx = (zd_scout_context_t*)context;

  // 1. Extract ZID (16 bytes)
  z_id_t zid = z_hello_zid(hello);

  // 2. Extract whatami
  z_whatami_t whatami = z_hello_whatami(hello);

  // 3. Extract locators as semicolon-separated string
  z_owned_string_array_t locators;
  z_hello_locators(hello, &locators);
  const z_loaned_string_array_t* locs_loaned = z_string_array_loan(&locators);
  size_t loc_count = z_string_array_len(locs_loaned);

  // Build locator string
  char* loc_buf = NULL;
  size_t loc_buf_len = 0;
  if (loc_count > 0) {
    // First pass: compute total length
    for (size_t i = 0; i < loc_count; i++) {
      const z_loaned_string_t* loc = z_string_array_get(locs_loaned, i);
      loc_buf_len += z_string_len(loc);
      if (i < loc_count - 1) loc_buf_len += 1; // semicolon
    }
    loc_buf = (char*)malloc(loc_buf_len + 1);
    size_t offset = 0;
    for (size_t i = 0; i < loc_count; i++) {
      const z_loaned_string_t* loc = z_string_array_get(locs_loaned, i);
      size_t len = z_string_len(loc);
      memcpy(loc_buf + offset, z_string_data(loc), len);
      offset += len;
      if (i < loc_count - 1) {
        loc_buf[offset] = ';';
        offset++;
      }
    }
    loc_buf[loc_buf_len] = '\0';
  } else {
    loc_buf = (char*)malloc(1);
    loc_buf[0] = '\0';
  }

  z_string_array_drop(z_string_array_move(&locators));

  // Build Dart_CObject array: [zid_bytes, whatami_int, locators_str]
  Dart_CObject c_zid;
  c_zid.type = Dart_CObject_kTypedData;
  c_zid.value.as_typed_data.type = Dart_TypedData_kUint8;
  c_zid.value.as_typed_data.length = 16;
  c_zid.value.as_typed_data.values = zid.id;

  Dart_CObject c_whatami;
  c_whatami.type = Dart_CObject_kInt64;
  c_whatami.value.as_int64 = (int64_t)whatami;

  Dart_CObject c_locators;
  c_locators.type = Dart_CObject_kString;
  c_locators.value.as_string = loc_buf;

  Dart_CObject* elements[3] = {&c_zid, &c_whatami, &c_locators};
  Dart_CObject c_array;
  c_array.type = Dart_CObject_kArray;
  c_array.value.as_array.length = 3;
  c_array.value.as_array.values = elements;

  Dart_PostCObject_DL(ctx->dart_port, &c_array);

  free(loc_buf);
}

FFI_PLUGIN_EXPORT int zd_scout(z_owned_config_t* config, int64_t dart_port,
                               uint64_t timeout_ms, int what) {
  zd_scout_context_t ctx = { .dart_port = (Dart_Port_DL)dart_port };

  z_owned_closure_hello_t closure;
  z_closure_hello(&closure, _zd_scout_hello_callback, NULL, &ctx);

  z_scout_options_t opts;
  z_scout_options_default(&opts);
  opts.timeout_ms = timeout_ms;
  opts.what = (z_what_t)what;

  z_result_t res;
  if (config != NULL) {
    res = z_scout(z_config_move(config), z_closure_hello_move(&closure), &opts);
  } else {
    z_owned_config_t default_config;
    z_config_default(&default_config);
    res = z_scout(z_config_move(&default_config),
                  z_closure_hello_move(&closure), &opts);
  }

  // Post null sentinel to signal completion
  Dart_CObject null_obj;
  null_obj.type = Dart_CObject_kNull;
  Dart_PostCObject_DL(dart_port, &null_obj);

  return res;
}

FFI_PLUGIN_EXPORT int zd_whatami_to_view_string(int whatami,
                                                z_view_string_t* out) {
  return z_whatami_to_view_string((z_whatami_t)whatami, out);
}

// ---------------------------------------------------------------------------
// Queryable
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT int32_t zd_queryable_sizeof(void) {
  return (int32_t)sizeof(z_owned_queryable_t);
}

FFI_PLUGIN_EXPORT int32_t zd_query_sizeof(void) {
  return (int32_t)sizeof(z_owned_query_t);
}

/// Context struct for queryable callback.
typedef struct {
  Dart_Port_DL dart_port;
} zd_queryable_context_t;

/// Query callback: clones the query and posts fields to Dart via native port.
static void _zd_query_callback(z_loaned_query_t* query, void* context) {
  zd_queryable_context_t* ctx = (zd_queryable_context_t*)context;

  // 1. Clone query to heap (query is only valid during this callback)
  z_owned_query_t* cloned = (z_owned_query_t*)malloc(sizeof(z_owned_query_t));
  if (!cloned) return;
  z_query_clone(cloned, query);

  // 2. Key expression as string
  const z_loaned_keyexpr_t* ke = z_query_keyexpr(query);
  z_view_string_t key_view;
  z_keyexpr_as_view_string(ke, &key_view);
  const z_loaned_string_t* key_loaned = z_view_string_loan(&key_view);
  size_t key_len = z_string_len(key_loaned);
  const char* key_data = z_string_data(key_loaned);

  char* key_buf = (char*)malloc(key_len + 1);
  memcpy(key_buf, key_data, key_len);
  key_buf[key_len] = '\0';

  // 3. Parameters as string
  z_view_string_t params_view;
  z_query_parameters(query, &params_view);
  const z_loaned_string_t* params_loaned = z_view_string_loan(&params_view);
  size_t params_len = z_string_len(params_loaned);
  const char* params_data = z_string_data(params_loaned);

  char* params_buf = (char*)malloc(params_len + 1);
  memcpy(params_buf, params_data, params_len);
  params_buf[params_len] = '\0';

  // 4. Payload (nullable)
  const z_loaned_bytes_t* payload = z_query_payload(query);

  // Build Dart_CObject array: [query_ptr, keyexpr, params, payload_or_null]
  Dart_CObject c_query_ptr;
  c_query_ptr.type = Dart_CObject_kInt64;
  c_query_ptr.value.as_int64 = (int64_t)(intptr_t)cloned;

  Dart_CObject c_keyexpr;
  c_keyexpr.type = Dart_CObject_kString;
  c_keyexpr.value.as_string = key_buf;

  Dart_CObject c_params;
  c_params.type = Dart_CObject_kString;
  c_params.value.as_string = params_buf;

  Dart_CObject c_payload;
  z_owned_string_t payload_str;
  bool has_payload = (payload != NULL);
  if (has_payload) {
    // Check if bytes are empty
    z_bytes_to_string(payload, &payload_str);
    const z_loaned_string_t* pl_loaned = z_string_loan(&payload_str);
    size_t pl_len = z_string_len(pl_loaned);
    if (pl_len > 0) {
      c_payload.type = Dart_CObject_kTypedData;
      c_payload.value.as_typed_data.type = Dart_TypedData_kUint8;
      c_payload.value.as_typed_data.length = (intptr_t)pl_len;
      c_payload.value.as_typed_data.values = (uint8_t*)z_string_data(pl_loaned);
    } else {
      has_payload = false;
      c_payload.type = Dart_CObject_kNull;
    }
  } else {
    c_payload.type = Dart_CObject_kNull;
  }

  Dart_CObject* elements[4] = {&c_query_ptr, &c_keyexpr, &c_params, &c_payload};
  Dart_CObject c_array;
  c_array.type = Dart_CObject_kArray;
  c_array.value.as_array.length = 4;
  c_array.value.as_array.values = elements;

  Dart_PostCObject_DL(ctx->dart_port, &c_array);

  // Cleanup temporary buffers
  free(key_buf);
  free(params_buf);
  if (has_payload) {
    z_string_drop(z_string_move(&payload_str));
  }
}

/// Drop callback for queryable context.
static void _zd_queryable_drop(void* context) {
  free(context);
}

FFI_PLUGIN_EXPORT int8_t zd_declare_queryable(
    uint8_t* queryable_out,
    const uint8_t* session,
    const char* key_expr,
    int64_t port,
    int8_t complete) {
  // Create key expression view
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  zd_queryable_context_t* ctx =
      (zd_queryable_context_t*)malloc(sizeof(zd_queryable_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)port;

  z_owned_closure_query_t callback;
  z_closure_query(&callback, _zd_query_callback, _zd_queryable_drop, ctx);

  z_queryable_options_t opts;
  z_queryable_options_default(&opts);
  opts.complete = (bool)complete;

  int rc = z_declare_queryable(
      (const z_loaned_session_t*)session,
      (z_owned_queryable_t*)queryable_out,
      z_view_keyexpr_loan(&ke),
      z_closure_query_move(&callback),
      &opts);

  if (rc != 0) {
    z_closure_query_drop(z_closure_query_move(&callback));
  }

  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT void zd_queryable_drop(uint8_t* queryable) {
  z_queryable_drop(z_queryable_move((z_owned_queryable_t*)queryable));
}

FFI_PLUGIN_EXPORT void zd_query_drop(uint8_t* query) {
  z_query_drop(z_query_move((z_owned_query_t*)query));
}

// ---------------------------------------------------------------------------
// Get (query with reply callback via NativePort)
// ---------------------------------------------------------------------------

/// Context struct for get reply callback.
typedef struct {
  Dart_Port_DL dart_port;
} zd_get_context_t;

/// Reply callback: extracts reply fields and posts to Dart via native port.
/// Ok reply: [1, keyexpr_string, payload_bytes, kind_int, attachment_or_null, encoding_string]
/// Error reply: [0, error_payload_bytes, error_encoding_string]
static void _zd_reply_callback(z_loaned_reply_t* reply, void* context) {
  zd_get_context_t* ctx = (zd_get_context_t*)context;

  if (z_reply_is_ok(reply)) {
    const z_loaned_sample_t* sample = z_reply_ok(reply);

    // 1. Key expression as string
    const z_loaned_keyexpr_t* ke = z_sample_keyexpr(sample);
    z_view_string_t key_view;
    z_keyexpr_as_view_string(ke, &key_view);
    const z_loaned_string_t* key_loaned = z_view_string_loan(&key_view);
    size_t key_len = z_string_len(key_loaned);
    const char* key_data = z_string_data(key_loaned);

    char* key_buf = (char*)malloc(key_len + 1);
    memcpy(key_buf, key_data, key_len);
    key_buf[key_len] = '\0';

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

    // Build tag
    Dart_CObject c_tag;
    c_tag.type = Dart_CObject_kInt64;
    c_tag.value.as_int64 = 1;

    Dart_CObject c_keyexpr;
    c_keyexpr.type = Dart_CObject_kString;
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

    char* enc_buf = (char*)malloc(enc_len + 1);
    memcpy(enc_buf, enc_data, enc_len);
    enc_buf[enc_len] = '\0';

    Dart_CObject c_encoding;
    c_encoding.type = Dart_CObject_kString;
    c_encoding.value.as_string = enc_buf;

    Dart_CObject* elements[6] = {&c_tag, &c_keyexpr, &c_payload, &c_kind, &c_attachment, &c_encoding};
    Dart_CObject c_array;
    c_array.type = Dart_CObject_kArray;
    c_array.value.as_array.length = 6;
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
  } else {
    // Error reply
    const z_loaned_reply_err_t* err = z_reply_err(reply);

    // Error payload as bytes
    const z_loaned_bytes_t* err_payload = z_reply_err_payload(err);
    z_owned_string_t err_payload_str;
    z_bytes_to_string(err_payload, &err_payload_str);
    const z_loaned_string_t* err_pl_loaned = z_string_loan(&err_payload_str);
    size_t err_pl_len = z_string_len(err_pl_loaned);
    const char* err_pl_data = z_string_data(err_pl_loaned);

    // Error encoding as string
    const z_loaned_encoding_t* err_encoding = z_reply_err_encoding(err);
    z_owned_string_t err_enc_str;
    z_encoding_to_string(err_encoding, &err_enc_str);
    const z_loaned_string_t* err_enc_loaned = z_string_loan(&err_enc_str);
    size_t err_enc_len = z_string_len(err_enc_loaned);
    const char* err_enc_data = z_string_data(err_enc_loaned);

    Dart_CObject c_tag;
    c_tag.type = Dart_CObject_kInt64;
    c_tag.value.as_int64 = 0;

    Dart_CObject c_err_payload;
    c_err_payload.type = Dart_CObject_kTypedData;
    c_err_payload.value.as_typed_data.type = Dart_TypedData_kUint8;
    c_err_payload.value.as_typed_data.length = (intptr_t)err_pl_len;
    c_err_payload.value.as_typed_data.values = (uint8_t*)err_pl_data;

    char* err_enc_buf = (char*)malloc(err_enc_len + 1);
    memcpy(err_enc_buf, err_enc_data, err_enc_len);
    err_enc_buf[err_enc_len] = '\0';

    Dart_CObject c_err_encoding;
    c_err_encoding.type = Dart_CObject_kString;
    c_err_encoding.value.as_string = err_enc_buf;

    Dart_CObject* elements[3] = {&c_tag, &c_err_payload, &c_err_encoding};
    Dart_CObject c_array;
    c_array.type = Dart_CObject_kArray;
    c_array.value.as_array.length = 3;
    c_array.value.as_array.values = elements;

    Dart_PostCObject_DL(ctx->dart_port, &c_array);

    free(err_enc_buf);
    z_string_drop(z_string_move(&err_payload_str));
    z_string_drop(z_string_move(&err_enc_str));
  }
}

/// Drop callback for get context: posts null sentinel and frees context.
static void _zd_get_drop(void* context) {
  zd_get_context_t* ctx = (zd_get_context_t*)context;

  // Post null sentinel to signal completion to Dart
  Dart_CObject null_obj;
  null_obj.type = Dart_CObject_kNull;
  Dart_PostCObject_DL(ctx->dart_port, &null_obj);

  free(ctx);
}

FFI_PLUGIN_EXPORT int8_t zd_get(
    const uint8_t* session,
    const char* selector,
    int64_t port,
    int8_t target,
    int8_t consolidation,
    uint8_t* payload,
    const char* encoding,
    uint64_t timeout_ms,
    const char* parameters) {
  // Create key expression view from selector
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, selector) != 0) {
    return -1;
  }

  zd_get_context_t* ctx =
      (zd_get_context_t*)malloc(sizeof(zd_get_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)port;

  z_owned_closure_reply_t callback;
  z_closure_reply(&callback, _zd_reply_callback, _zd_get_drop, ctx);

  z_get_options_t opts;
  z_get_options_default(&opts);
  opts.target = (z_query_target_t)target;
  opts.timeout_ms = timeout_ms;

  if (consolidation == -1) {
    opts.consolidation = z_query_consolidation_default();
  } else {
    opts.consolidation.mode = (z_consolidation_mode_t)consolidation;
  }

  // Optional payload (z_owned_bytes_t*, consumed via move)
  if (payload != NULL) {
    opts.payload = z_bytes_move((z_owned_bytes_t*)payload);
  }

  // Optional encoding
  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
  }

  int rc = z_get(
      (const z_loaned_session_t*)session,
      z_view_keyexpr_loan(&ke),
      parameters,
      z_closure_reply_move(&callback),
      &opts);

  if (rc != 0) {
    z_closure_reply_drop(z_closure_reply_move(&callback));
  }

  return (int8_t)rc;
}

// ---------------------------------------------------------------------------
// Query reply
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT int8_t zd_query_reply(
    const uint8_t* query,
    const char* key_expr,
    uint8_t* payload,
    const char* encoding) {
  // Loan the cloned query
  const z_loaned_query_t* loaned = z_query_loan((z_owned_query_t*)query);

  // Create key expression view
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  // Options
  z_query_reply_options_t opts;
  z_query_reply_options_default(&opts);

  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
  }

  int rc = z_query_reply(
      loaned,
      z_view_keyexpr_loan(&ke),
      z_bytes_move((z_owned_bytes_t*)payload),
      &opts);

  return (int8_t)rc;
}

// ---------------------------------------------------------------------------
// Query accessors
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT const char* zd_query_keyexpr(const uint8_t* query) {
  const z_loaned_query_t* loaned = z_query_loan((z_owned_query_t*)query);
  const z_loaned_keyexpr_t* ke = z_query_keyexpr(loaned);
  z_view_string_t str;
  z_keyexpr_as_view_string(ke, &str);
  const z_loaned_string_t* loaned_str = z_view_string_loan(&str);
  // Return pointer into query's internal storage -- valid while query lives
  return z_string_data(loaned_str);
}

FFI_PLUGIN_EXPORT const char* zd_query_parameters(const uint8_t* query) {
  const z_loaned_query_t* loaned = z_query_loan((z_owned_query_t*)query);
  z_view_string_t params;
  z_query_parameters(loaned, &params);
  const z_loaned_string_t* loaned_str = z_view_string_loan(&params);
  return z_string_data(loaned_str);
}

FFI_PLUGIN_EXPORT int32_t zd_query_payload(
    const uint8_t* query,
    uint8_t* payload_out,
    int32_t max_len) {
  const z_loaned_query_t* loaned = z_query_loan((z_owned_query_t*)query);
  const z_loaned_bytes_t* payload = z_query_payload(loaned);
  if (payload == NULL) {
    return 0;
  }
  size_t actual_len = z_bytes_len(payload);
  if (actual_len == 0) {
    return 0;
  }
  // Copy payload bytes
  z_owned_string_t payload_str;
  z_bytes_to_string(payload, &payload_str);
  const z_loaned_string_t* pl_loaned = z_string_loan(&payload_str);
  size_t copy_len = actual_len < (size_t)max_len ? actual_len : (size_t)max_len;
  memcpy(payload_out, z_string_data(pl_loaned), copy_len);
  z_string_drop(z_string_move(&payload_str));
  return (int32_t)actual_len;
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

FFI_PLUGIN_EXPORT int8_t zd_bytes_is_shm(const uint8_t* bytes) {
  const z_owned_bytes_t* owned = (const z_owned_bytes_t*)bytes;
  const z_loaned_bytes_t* loaned = z_bytes_loan(owned);
  const z_loaned_shm_t* shm = NULL;
  z_result_t rc = z_bytes_as_loaned_shm(loaned, &shm);
  return (rc == 0) ? 1 : 0;
}

#endif // Z_FEATURE_SHARED_MEMORY && Z_FEATURE_UNSTABLE_API

// ---------------------------------------------------------------------------
// Pull Subscriber (ring channel)
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT int32_t zd_ring_handler_sample_sizeof(void) {
  return (int32_t)sizeof(z_owned_ring_handler_sample_t);
}

FFI_PLUGIN_EXPORT int8_t zd_declare_pull_subscriber(
    uint8_t* subscriber_out, uint8_t* handler_out,
    const uint8_t* session, const char* key_expr,
    int32_t capacity) {
  // Validate key expression
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  // Create ring channel
  z_owned_closure_sample_t closure;
  z_ring_channel_sample_new(
      &closure,
      (z_owned_ring_handler_sample_t*)handler_out,
      (size_t)capacity);

  // Declare subscriber with ring closure
  int rc = z_declare_subscriber(
      (const z_loaned_session_t*)session,
      (z_owned_subscriber_t*)subscriber_out,
      z_view_keyexpr_loan(&ke),
      z_closure_sample_move(&closure),
      NULL);

  if (rc != 0) {
    // On failure, drop the ring handler (closure was not consumed)
    z_ring_handler_sample_drop(
        z_ring_handler_sample_move((z_owned_ring_handler_sample_t*)handler_out));
  }

  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT int8_t zd_pull_subscriber_try_recv(
    const uint8_t* handler,
    char** out_keyexpr, uint8_t** out_payload, int32_t* out_payload_len,
    int8_t* out_kind, char** out_encoding,
    uint8_t** out_attachment, int32_t* out_attachment_len) {
  const z_loaned_ring_handler_sample_t* h =
      z_ring_handler_sample_loan((const z_owned_ring_handler_sample_t*)handler);

  z_owned_sample_t sample;
  z_result_t res = z_ring_handler_sample_try_recv(h, &sample);

  if (res == Z_CHANNEL_DISCONNECTED) {
    return 1;  // channel disconnected
  }
  if (res == Z_CHANNEL_NODATA) {
    return 2;  // buffer empty
  }

  // res == Z_OK: extract sample fields
  const z_loaned_sample_t* s = z_sample_loan(&sample);

  // 1. Key expression
  z_view_string_t key_view;
  z_keyexpr_as_view_string(z_sample_keyexpr(s), &key_view);
  const z_loaned_string_t* key_loaned = z_view_string_loan(&key_view);
  size_t key_len = z_string_len(key_loaned);
  const char* key_data = z_string_data(key_loaned);
  *out_keyexpr = (char*)malloc(key_len + 1);
  memcpy(*out_keyexpr, key_data, key_len);
  (*out_keyexpr)[key_len] = '\0';

  // 2. Payload as bytes (via string conversion, matching existing pattern)
  const z_loaned_bytes_t* payload_loaned = z_sample_payload(s);
  size_t payload_byte_len = z_bytes_len(payload_loaned);
  if (payload_byte_len > 0) {
    z_owned_string_t payload_str;
    z_bytes_to_string(payload_loaned, &payload_str);
    const z_loaned_string_t* pl_loaned = z_string_loan(&payload_str);
    size_t pl_len = z_string_len(pl_loaned);
    const char* pl_data = z_string_data(pl_loaned);
    *out_payload = (uint8_t*)malloc(pl_len);
    memcpy(*out_payload, pl_data, pl_len);
    *out_payload_len = (int32_t)pl_len;
    z_string_drop(z_string_move(&payload_str));
  } else {
    *out_payload = NULL;
    *out_payload_len = 0;
  }

  // 3. Kind
  *out_kind = (int8_t)z_sample_kind(s);

  // 4. Encoding
  const z_loaned_encoding_t* encoding = z_sample_encoding(s);
  z_owned_string_t enc_str;
  z_encoding_to_string(encoding, &enc_str);
  const z_loaned_string_t* enc_loaned = z_string_loan(&enc_str);
  size_t enc_len = z_string_len(enc_loaned);
  const char* enc_data = z_string_data(enc_loaned);
  if (enc_len > 0) {
    *out_encoding = (char*)malloc(enc_len + 1);
    memcpy(*out_encoding, enc_data, enc_len);
    (*out_encoding)[enc_len] = '\0';
  } else {
    *out_encoding = NULL;
  }
  z_string_drop(z_string_move(&enc_str));

  // 5. Attachment (nullable)
  const z_loaned_bytes_t* attachment = z_sample_attachment(s);
  if (attachment != NULL) {
    z_owned_string_t att_str;
    z_bytes_to_string(attachment, &att_str);
    const z_loaned_string_t* att_loaned = z_string_loan(&att_str);
    size_t att_len = z_string_len(att_loaned);
    const char* att_data = z_string_data(att_loaned);
    *out_attachment = (uint8_t*)malloc(att_len);
    memcpy(*out_attachment, att_data, att_len);
    *out_attachment_len = (int32_t)att_len;
    z_string_drop(z_string_move(&att_str));
  } else {
    *out_attachment = NULL;
    *out_attachment_len = 0;
  }

  // Drop the owned sample
  z_sample_drop(z_sample_move(&sample));

  return 0;  // success
}

FFI_PLUGIN_EXPORT void zd_ring_handler_sample_drop(uint8_t* handler) {
  z_owned_ring_handler_sample_t* h = (z_owned_ring_handler_sample_t*)handler;
  z_ring_handler_sample_drop(z_ring_handler_sample_move(h));
}

// ---------------------------------------------------------------------------
// Querier
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_querier_sizeof(void) {
  return sizeof(z_owned_querier_t);
}

FFI_PLUGIN_EXPORT int8_t zd_declare_querier(
    uint8_t* querier_out, const uint8_t* session,
    const char* key_expr, int8_t target,
    int8_t consolidation, uint64_t timeout_ms) {
  // Create key expression view
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  z_querier_options_t opts;
  z_querier_options_default(&opts);

  opts.target = (z_query_target_t)target;

  if (consolidation == -1) {
    opts.consolidation = z_query_consolidation_default();
  } else {
    opts.consolidation.mode = (z_consolidation_mode_t)consolidation;
  }

  if (timeout_ms > 0) {
    opts.timeout_ms = timeout_ms;
  }

  return (int8_t)z_declare_querier(
      (const z_loaned_session_t*)session,
      (z_owned_querier_t*)querier_out,
      z_view_keyexpr_loan(&ke),
      &opts);
}

FFI_PLUGIN_EXPORT void zd_querier_drop(uint8_t* querier) {
  z_querier_drop(z_querier_move((z_owned_querier_t*)querier));
}

FFI_PLUGIN_EXPORT int8_t zd_querier_get(
    const uint8_t* querier, const char* parameters,
    int64_t port, uint8_t* payload, const char* encoding) {
  const z_loaned_querier_t* loaned =
      z_querier_loan((const z_owned_querier_t*)querier);

  zd_get_context_t* ctx =
      (zd_get_context_t*)malloc(sizeof(zd_get_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)port;

  z_owned_closure_reply_t callback;
  z_closure_reply(&callback, _zd_reply_callback, _zd_get_drop, ctx);

  z_querier_get_options_t opts;
  z_querier_get_options_default(&opts);

  // Optional payload (z_owned_bytes_t*, consumed via move)
  if (payload != NULL) {
    opts.payload = z_bytes_move((z_owned_bytes_t*)payload);
  }

  // Optional encoding
  z_owned_encoding_t owned_encoding;
  if (encoding != NULL) {
    z_encoding_from_str(&owned_encoding, encoding);
    opts.encoding = z_encoding_move(&owned_encoding);
  }

  int rc = z_querier_get(
      loaned,
      parameters,
      z_closure_reply_move(&callback),
      &opts);

  if (rc != 0) {
    z_closure_reply_drop(z_closure_reply_move(&callback));
  }

  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT int8_t zd_querier_declare_background_matching_listener(
    const uint8_t* querier, int64_t dart_port) {
  const z_loaned_querier_t* loaned =
      z_querier_loan((const z_owned_querier_t*)querier);

  zd_matching_context_t* ctx =
      (zd_matching_context_t*)malloc(sizeof(zd_matching_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)dart_port;

  z_owned_closure_matching_status_t callback;
  z_closure_matching_status(
      &callback, _zd_matching_status_callback, _zd_matching_drop, ctx);

  int rc = z_querier_declare_background_matching_listener(
      loaned, z_closure_matching_status_move(&callback));

  if (rc != 0) {
    z_closure_matching_status_drop(z_closure_matching_status_move(&callback));
  }

  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT int8_t zd_querier_get_matching_status(
    const uint8_t* querier, int8_t* matching_out) {
  const z_loaned_querier_t* loaned =
      z_querier_loan((const z_owned_querier_t*)querier);

  z_matching_status_t status;
  int rc = z_querier_get_matching_status(loaned, &status);
  if (rc == 0) {
    *matching_out = status.matching ? 1 : 0;
  }
  return (int8_t)rc;
}

// ---------------------------------------------------------------------------
// Liveliness
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT size_t zd_liveliness_token_sizeof(void) {
  return sizeof(z_owned_liveliness_token_t);
}

FFI_PLUGIN_EXPORT int8_t zd_liveliness_declare_token(
    uint8_t* token_out, const uint8_t* session, const char* key_expr) {
  const z_loaned_session_t* loaned_session =
      (const z_loaned_session_t*)session;

  // Validate key expression
  z_view_keyexpr_t ke;
  int rc = z_view_keyexpr_from_str(&ke, key_expr);
  if (rc != 0) return (int8_t)rc;

  z_owned_liveliness_token_t* token = (z_owned_liveliness_token_t*)token_out;
  rc = z_liveliness_declare_token(
      loaned_session, token, z_view_keyexpr_loan(&ke), NULL);
  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT void zd_liveliness_token_drop(uint8_t* token) {
  z_owned_liveliness_token_t* t = (z_owned_liveliness_token_t*)token;
  z_liveliness_token_drop(z_liveliness_token_move(t));
}

FFI_PLUGIN_EXPORT int8_t zd_liveliness_declare_subscriber(
    uint8_t* subscriber_out, const uint8_t* session,
    const char* key_expr, int64_t port, int8_t history) {
  const z_loaned_session_t* loaned_session =
      (const z_loaned_session_t*)session;

  // Validate key expression
  z_view_keyexpr_t ke;
  int rc = z_view_keyexpr_from_str(&ke, key_expr);
  if (rc != 0) return (int8_t)rc;

  // Allocate context for the sample callback
  zd_subscriber_context_t* ctx =
      (zd_subscriber_context_t*)malloc(sizeof(zd_subscriber_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)port;

  // Create closure reusing the existing sample callback/drop
  z_owned_closure_sample_t callback;
  z_closure_sample(&callback, _zd_sample_callback, _zd_sample_drop, ctx);

  // Set up options with history flag
  z_liveliness_subscriber_options_t opts;
  z_liveliness_subscriber_options_default(&opts);
  opts.history = history ? true : false;

  z_owned_subscriber_t* subscriber = (z_owned_subscriber_t*)subscriber_out;
  rc = z_liveliness_declare_subscriber(
      loaned_session, subscriber, z_view_keyexpr_loan(&ke),
      z_closure_sample_move(&callback), &opts);

  if (rc != 0) {
    z_closure_sample_drop(z_closure_sample_move(&callback));
  }

  return (int8_t)rc;
}

FFI_PLUGIN_EXPORT int8_t zd_liveliness_get(
    const uint8_t* session, const char* key_expr,
    int64_t port, uint64_t timeout_ms) {
  // Validate key expression
  z_view_keyexpr_t ke;
  if (z_view_keyexpr_from_str(&ke, key_expr) != 0) {
    return -1;
  }

  zd_get_context_t* ctx =
      (zd_get_context_t*)malloc(sizeof(zd_get_context_t));
  if (!ctx) return -1;
  ctx->dart_port = (Dart_Port_DL)port;

  z_owned_closure_reply_t callback;
  z_closure_reply(&callback, _zd_reply_callback, _zd_get_drop, ctx);

  z_liveliness_get_options_t opts;
  z_liveliness_get_options_default(&opts);
  opts.timeout_ms = timeout_ms;

  int rc = z_liveliness_get(
      (const z_loaned_session_t*)session,
      z_view_keyexpr_loan(&ke),
      z_closure_reply_move(&callback),
      &opts);

  if (rc != 0) {
    z_closure_reply_drop(z_closure_reply_move(&callback));
  }

  return (int8_t)rc;
}

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

size_t zd_serializer_sizeof(void) {
  return sizeof(ze_owned_serializer_t);
}

int8_t zd_serializer_empty(ze_owned_serializer_t* ser) {
  return (int8_t)ze_serializer_empty(ser);
}

void zd_serializer_loan_mut(
    ze_owned_serializer_t* ser, ze_loaned_serializer_t** out) {
  *out = ze_serializer_loan_mut(ser);
}

void zd_serializer_finish(
    ze_owned_serializer_t* ser, z_owned_bytes_t* out) {
  ze_serializer_finish(ze_serializer_move(ser), out);
}

void zd_serializer_drop(ze_owned_serializer_t* ser) {
  ze_serializer_drop(ze_serializer_move(ser));
}

// ---------------------------------------------------------------------------
// Serializer — arithmetic type serialization
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_uint8(ze_loaned_serializer_t* ser, uint8_t val) {
  return (int8_t)ze_serializer_serialize_uint8(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_uint16(ze_loaned_serializer_t* ser, uint16_t val) {
  return (int8_t)ze_serializer_serialize_uint16(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_uint32(ze_loaned_serializer_t* ser, uint32_t val) {
  return (int8_t)ze_serializer_serialize_uint32(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_uint64(ze_loaned_serializer_t* ser, uint64_t val) {
  return (int8_t)ze_serializer_serialize_uint64(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_int8(ze_loaned_serializer_t* ser, int8_t val) {
  return (int8_t)ze_serializer_serialize_int8(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_int16(ze_loaned_serializer_t* ser, int16_t val) {
  return (int8_t)ze_serializer_serialize_int16(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_int32(ze_loaned_serializer_t* ser, int32_t val) {
  return (int8_t)ze_serializer_serialize_int32(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_int64(ze_loaned_serializer_t* ser, int64_t val) {
  return (int8_t)ze_serializer_serialize_int64(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_float(ze_loaned_serializer_t* ser, float val) {
  return (int8_t)ze_serializer_serialize_float(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_double(ze_loaned_serializer_t* ser, double val) {
  return (int8_t)ze_serializer_serialize_double(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_bool(ze_loaned_serializer_t* ser, bool val) {
  return (int8_t)ze_serializer_serialize_bool(ser, val);
}

// ---------------------------------------------------------------------------
// Serializer — compound type serialization
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_string(ze_loaned_serializer_t* ser, const char* val) {
  return (int8_t)ze_serializer_serialize_str(ser, val);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_buf(ze_loaned_serializer_t* ser, const uint8_t* data, size_t len) {
  return (int8_t)ze_serializer_serialize_buf(ser, data, len);
}

FFI_PLUGIN_EXPORT
int8_t zd_serializer_serialize_sequence_length(ze_loaned_serializer_t* ser, size_t len) {
  return (int8_t)ze_serializer_serialize_sequence_length(ser, len);
}

// ---------------------------------------------------------------------------
// Deserializer
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
size_t zd_deserializer_sizeof(void) {
  return sizeof(ze_deserializer_t);
}

FFI_PLUGIN_EXPORT
void zd_deserializer_from_bytes(const z_loaned_bytes_t* bytes, ze_deserializer_t* out) {
  *out = ze_deserializer_from_bytes(bytes);
}

FFI_PLUGIN_EXPORT
bool zd_deserializer_is_done(const ze_deserializer_t* deser) {
  return ze_deserializer_is_done(deser);
}

// ---------------------------------------------------------------------------
// Deserializer — type deserialization
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_uint8(ze_deserializer_t* deser, uint8_t* out) {
  return (int8_t)ze_deserializer_deserialize_uint8(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_uint16(ze_deserializer_t* deser, uint16_t* out) {
  return (int8_t)ze_deserializer_deserialize_uint16(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_uint32(ze_deserializer_t* deser, uint32_t* out) {
  return (int8_t)ze_deserializer_deserialize_uint32(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_uint64(ze_deserializer_t* deser, uint64_t* out) {
  return (int8_t)ze_deserializer_deserialize_uint64(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_int8(ze_deserializer_t* deser, int8_t* out) {
  return (int8_t)ze_deserializer_deserialize_int8(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_int16(ze_deserializer_t* deser, int16_t* out) {
  return (int8_t)ze_deserializer_deserialize_int16(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_int32(ze_deserializer_t* deser, int32_t* out) {
  return (int8_t)ze_deserializer_deserialize_int32(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_int64(ze_deserializer_t* deser, int64_t* out) {
  return (int8_t)ze_deserializer_deserialize_int64(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_float(ze_deserializer_t* deser, float* out) {
  return (int8_t)ze_deserializer_deserialize_float(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_double(ze_deserializer_t* deser, double* out) {
  return (int8_t)ze_deserializer_deserialize_double(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_bool(ze_deserializer_t* deser, bool* out) {
  return (int8_t)ze_deserializer_deserialize_bool(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_string(ze_deserializer_t* deser, z_owned_string_t* out) {
  return (int8_t)ze_deserializer_deserialize_string(deser, out);
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_buf(ze_deserializer_t* deser, z_owned_bytes_t* out) {
  z_owned_slice_t slice;
  z_result_t rc = ze_deserializer_deserialize_slice(deser, &slice);
  if (rc != 0) return (int8_t)rc;
  z_bytes_from_slice(out, z_slice_move(&slice));
  return 0;
}

FFI_PLUGIN_EXPORT
int8_t zd_deserializer_deserialize_sequence_length(ze_deserializer_t* deser, size_t* out) {
  return (int8_t)ze_deserializer_deserialize_sequence_length(deser, out);
}

// ---------------------------------------------------------------------------
// Bytes Writer
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
size_t zd_bytes_writer_sizeof(void) {
  return sizeof(z_owned_bytes_writer_t);
}

FFI_PLUGIN_EXPORT
int8_t zd_bytes_writer_empty(z_owned_bytes_writer_t* writer) {
  return (int8_t)z_bytes_writer_empty(writer);
}

FFI_PLUGIN_EXPORT
void zd_bytes_writer_loan_mut(
    z_owned_bytes_writer_t* writer, z_loaned_bytes_writer_t** out) {
  *out = z_bytes_writer_loan_mut(writer);
}

FFI_PLUGIN_EXPORT
int8_t zd_bytes_writer_write_all(
    z_loaned_bytes_writer_t* writer, const uint8_t* data, size_t len) {
  return (int8_t)z_bytes_writer_write_all(writer, data, len);
}

FFI_PLUGIN_EXPORT
int8_t zd_bytes_writer_append(
    z_loaned_bytes_writer_t* writer, z_owned_bytes_t* bytes) {
  return (int8_t)z_bytes_writer_append(writer, z_bytes_move(bytes));
}

FFI_PLUGIN_EXPORT
void zd_bytes_writer_finish(
    z_owned_bytes_writer_t* writer, z_owned_bytes_t* out) {
  z_bytes_writer_finish(z_bytes_writer_move(writer), out);
}

FFI_PLUGIN_EXPORT
void zd_bytes_writer_drop(z_owned_bytes_writer_t* writer) {
  z_bytes_writer_drop(z_bytes_writer_move(writer));
}

// ---------------------------------------------------------------------------
// Bytes Slice Iterator
// ---------------------------------------------------------------------------

FFI_PLUGIN_EXPORT
size_t zd_bytes_slice_iterator_sizeof(void) {
  return sizeof(z_bytes_slice_iterator_t);
}

FFI_PLUGIN_EXPORT
void zd_bytes_get_slice_iterator(
    const z_loaned_bytes_t* bytes, z_bytes_slice_iterator_t* iter) {
  *iter = z_bytes_get_slice_iterator(bytes);
}

FFI_PLUGIN_EXPORT
bool zd_bytes_slice_iterator_next(
    z_bytes_slice_iterator_t* iter, z_view_slice_t* out) {
  return z_bytes_slice_iterator_next(iter, out);
}

FFI_PLUGIN_EXPORT
size_t zd_view_slice_sizeof(void) {
  return sizeof(z_view_slice_t);
}

FFI_PLUGIN_EXPORT
const uint8_t* zd_view_slice_data(const z_view_slice_t* slice) {
  const z_loaned_slice_t* loaned = z_view_slice_loan(slice);
  return z_slice_data(loaned);
}

FFI_PLUGIN_EXPORT
size_t zd_view_slice_len(const z_view_slice_t* slice) {
  const z_loaned_slice_t* loaned = z_view_slice_loan(slice);
  return z_slice_len(loaned);
}
