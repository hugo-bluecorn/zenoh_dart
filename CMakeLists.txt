cmake_minimum_required(VERSION 3.16)
project(zenoh_dart VERSION 0.0.1 LANGUAGES C CXX)
# CXX required because zenoh-c's project() declares both C and CXX

# Reuse zenoh-c's battle-tested helpers
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/extern/zenoh-c/cmake"
                      ${CMAKE_MODULE_PATH})
include(helpers)
set_default_build_type(Release)

# ── Options ──
declare_cache_var(ZENOH_DART_BUILD_ZENOHC TRUE BOOL
    "Build zenoh-c from source via cargo (FALSE = use prebuilt)")

# ── Platform guard ──
if(NOT (UNIX OR ANDROID))
    message(FATAL_ERROR "Only Linux and Android targets are supported")
endif()
if(ANDROID)
    # cargo-ndk builds zenoh-c separately; CMake only builds the C shim here
    set(ZENOH_DART_BUILD_ZENOHC FALSE)
endif()

# ── zenoh-c (from source) ──
if(ZENOH_DART_BUILD_ZENOHC)
    # These cache vars configure zenoh-c's CMakeLists.txt before add_subdirectory
    set(BUILD_SHARED_LIBS TRUE CACHE BOOL "" FORCE)
    set(ZENOHC_BUILD_WITH_SHARED_MEMORY TRUE CACHE BOOL "" FORCE)
    set(ZENOHC_BUILD_WITH_UNSTABLE_API TRUE CACHE BOOL "" FORCE)
    # "+1.85.0" makes cargo invoke `cargo +1.85.0 build ...`
    # This overrides extern/zenoh-c/rust-toolchain.toml which pins an unreleased version.
    # Pinned to 1.85.0 because zenoh-c 1.7.2's transitive dep `static_init` 1.0.3
    # fails to compile on Rust >= 1.86 (parking_lot resolution error).
    set(ZENOHC_CARGO_CHANNEL "+1.85.0" CACHE STRING "" FORCE)
    # Note: ZENOHC_BUILD_IN_SOURCE_TREE is irrelevant here — zenoh-c's condition
    # (line 79) also checks CMAKE_SOURCE_DIR == CMAKE_CURRENT_SOURCE_DIR, which
    # is always FALSE when used via add_subdirectory(). No need to set it.
    add_subdirectory(extern/zenoh-c)
    message(STATUS "zenoh-c: building from source (cargo +1.85.0)")
else()
    message(STATUS "zenoh-c: using prebuilt (discovery in src/CMakeLists.txt)")
endif()

# ── C shim ──
add_subdirectory(src)

# ── Install: copy both .so files to the prebuilt directory ──
# Uses absolute DESTINATION intentionally — CMake install normally uses
# CMAKE_INSTALL_PREFIX + relative path, but we need libraries placed into
# the Dart package's native/ directory (which the build hook reads), not
# a system prefix like /usr/local/lib.
set(NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/package/native")

if(ANDROID)
    set(PREBUILT_DIR "${NATIVE_DIR}/android/${ANDROID_ABI}")
else()
    set(PREBUILT_DIR "${NATIVE_DIR}/linux/${CMAKE_SYSTEM_PROCESSOR}")
endif()

# Install libzenoh_dart.so via install(TARGETS) — NOT install(FILES).
# install(TARGETS) applies INSTALL_RPATH ("$ORIGIN") automatically via
# chrpath/relinking. install(FILES) is a raw copy that skips RPATH editing.
# This eliminates the patchelf dependency entirely.
install(TARGETS zenoh_dart LIBRARY DESTINATION "${PREBUILT_DIR}")

# Install libzenohc.so — source depends on build mode.
# zenohc_shared is an IMPORTED target, so install(TARGETS) cannot be used.
# install(FILES) is correct here — we don't own this library's RPATH.
if(ZENOH_DART_BUILD_ZENOHC AND TARGET zenohc_shared)
    # Superbuild: copy from cargo output in build tree
    install(FILES $<TARGET_FILE:zenohc_shared> DESTINATION "${PREBUILT_DIR}")
else()
    # Standalone/Android: libzenohc.so already in place (cargo-ndk or prior build)
    # Only copy if source differs from destination (avoids self-copy)
    if(DEFINED ZENOHC_LIB_DIR AND NOT "${ZENOHC_LIB_DIR}" STREQUAL "${PREBUILT_DIR}")
        install(FILES "${ZENOHC_LIB_DIR}/libzenohc.so" DESTINATION "${PREBUILT_DIR}")
    endif()
endif()
