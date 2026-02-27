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

# Dart API DL headers
target_include_directories(zenoh_dart PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/dart"
)

# ----------- zenoh-c library discovery -----------
# Resolve the real source dir (handles symlinks in pub cache)
get_filename_component(PACKAGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)

# zenoh-c headers
target_include_directories(zenoh_dart PUBLIC
  "${PACKAGE_ROOT}/extern/zenoh-c/include"
)

if(ANDROID)
  # Android: prebuilt in jniLibs (Gradle bundles these into APK automatically)
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/android/src/main/jniLibs/${ANDROID_ABI}")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
elseif(EXISTS "${PACKAGE_ROOT}/native/linux/${CMAKE_SYSTEM_PROCESSOR}/libzenohc.so")
  # Published package: prebuilt in native/ directory
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/native/linux/${CMAKE_SYSTEM_PROCESSOR}")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
else()
  # Developer fallback: locally built from submodule
  set(ZENOHC_LIB_DIR "${PACKAGE_ROOT}/extern/zenoh-c/target/release")
  set(ZENOHC_LIBRARY "${ZENOHC_LIB_DIR}/libzenohc.so")
endif()

# Validate library exists
if(NOT EXISTS "${ZENOHC_LIBRARY}")
  message(FATAL_ERROR
    "zenoh-c library not found at: ${ZENOHC_LIBRARY}\n"
    "For development: build zenoh-c with 'cmake --build extern/zenoh-c/build'\n"
    "For Android: run 'scripts/build_zenoh_android.sh'\n"
    "For published package: ensure native/ directory contains prebuilt libraries")
endif()

message(STATUS "Found zenoh-c: ${ZENOHC_LIBRARY}")

# Create IMPORTED target for zenohc
add_library(zenohc SHARED IMPORTED)
set_target_properties(zenohc PROPERTIES
  IMPORTED_LOCATION "${ZENOHC_LIBRARY}"
  IMPORTED_NO_SONAME TRUE
)

target_link_libraries(zenoh_dart PRIVATE zenohc)

# Propagate ZENOHC_LIB_DIR to parent scope (for bundled_libraries)
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
