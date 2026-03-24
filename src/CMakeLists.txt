cmake_minimum_required(VERSION 3.10)
project(zenoh_dart_library VERSION 0.0.1 LANGUAGES C)

add_library(zenoh_dart SHARED
  "zenoh_dart.c"
  "dart/dart_api_dl.c"
)

set_target_properties(zenoh_dart PROPERTIES
  PUBLIC_HEADER zenoh_dart.h
  OUTPUT_NAME "zenoh_dart"
  C_VISIBILITY_PRESET hidden
  POSITION_INDEPENDENT_CODE ON
)

target_compile_definitions(zenoh_dart PUBLIC DART_SHARED_LIB)
if(NOT ANDROID)
  target_compile_definitions(zenoh_dart PRIVATE
    Z_FEATURE_SHARED_MEMORY
    Z_FEATURE_UNSTABLE_API
  )
endif()

# Dart API DL headers
target_include_directories(zenoh_dart PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/dart"
)

# ── zenoh-c linkage ──
# Resolve the real source dir (handles symlinks in pub cache)
get_filename_component(PACKAGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)

if(TARGET zenohc::lib)
  # ── Superbuild mode: zenoh-c built by parent CMakeLists.txt ──
  # zenohc::lib's INTERFACE_INCLUDE_DIRECTORIES already provides the
  # zenoh-c headers, so no explicit target_include_directories needed.
  message(STATUS "zenoh-c: linking against zenohc::lib target (superbuild)")
  target_link_libraries(zenoh_dart PRIVATE zenohc::lib)

  # Resolve zenohc location for RPATH.
  # Uses zenohc_shared directly (not zenohc::lib) because:
  # 1. get_target_property() doesn't work on ALIAS targets before CMake 3.27
  # 2. We always want the shared library location regardless of BUILD_SHARED_LIBS
  get_target_property(ZENOHC_LOC zenohc_shared IMPORTED_LOCATION)
  if(ZENOHC_LOC)
    get_filename_component(ZENOHC_LIB_DIR "${ZENOHC_LOC}" DIRECTORY)
  endif()
else()
  # ── Standalone mode: 3-tier discovery (existing logic) ──
  # zenoh-c headers must be added explicitly
  target_include_directories(zenoh_dart PUBLIC
    "${PACKAGE_ROOT}/extern/zenoh-c/include"
  )

  if(ANDROID)
    set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/package/native/android/${ANDROID_ABI}")
    set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
  elseif(EXISTS "${PACKAGE_ROOT}/package/native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so")
    set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/package/native/linux/${CMAKE_SYSTEM_PROCESSOR}")
    set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
  else()
    set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/extern/zenoh-c/target/release")
    set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
  endif()

  if(NOT EXISTS "${ZENOHC_LIBRARY}")
    message(FATAL_ERROR
      "zenoh-c library not found at: ${ZENOHC_LIBRARY}\n"
      "For development: build from root with 'cmake --preset linux-x64'\n"
      "For Android: run 'scripts/build_zenoh_android.sh'\n"
      "For published package: ensure native/ directory contains prebuilt libraries")
  endif()

  message(STATUS "Found zenoh-c: ${ZENOHC_LIBRARY}")
  add_library(zenohc SHARED IMPORTED)
  set_target_properties(zenohc PROPERTIES
    IMPORTED_LOCATION "${ZENOHC_LIBRARY}"
    IMPORTED_NO_SONAME TRUE
  )
  target_link_libraries(zenoh_dart PRIVATE zenohc)
endif()

# Propagate ZENOHC_LIB_DIR to parent scope (for install target)
set(ZENOHC_LIB_DIR "${ZENOHC_LIB_DIR}" PARENT_SCOPE)

# Platform-specific settings
if(ANDROID)
  # Support Android 15 16k page size
  target_link_options(zenoh_dart PRIVATE "-Wl,-z,max-page-size=16384")
else()
  # RPATH: find zenohc at build time and in same directory at install time
  set_target_properties(zenoh_dart PROPERTIES
    BUILD_RPATH "${ZENOHC_LIB_DIR}"
    INSTALL_RPATH "$ORIGIN"
  )
endif()
