#include "zenoh_dart.h"
#include "dart/dart_api_dl.h"

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
