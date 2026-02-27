cmake_minimum_required(VERSION 3.10)
project(zenoh_dart C)

# Minimal standalone build: compiles only the C shim.
# zenoh-c linking is added in Phase 0 via TDD.

add_library(zenoh_dart SHARED
  zenoh_dart.c
)

target_include_directories(zenoh_dart PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)

set_target_properties(zenoh_dart PROPERTIES
  C_VISIBILITY_PRESET hidden
  POSITION_INDEPENDENT_CODE ON
)
