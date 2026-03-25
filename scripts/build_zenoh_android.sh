#!/usr/bin/env bash
set -euo pipefail

# Build zenoh-c for Android using cargo-ndk.
#
# Usage:
#   ./scripts/build_zenoh_android.sh                  # Build arm64-v8a + x86_64
#   ./scripts/build_zenoh_android.sh --abi arm64-v8a  # Build single ABI
#   ./scripts/build_zenoh_android.sh --all             # Build all 4 ABIs
#   ./scripts/build_zenoh_android.sh --api 26          # Override API level
#
# Environment:
#   ANDROID_NDK_HOME  Path to Android NDK (auto-detected from ~/Android/Sdk/ndk/)
#   API_LEVEL         Minimum Android API level (default: 24)

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ZENOHC_DIR="${PROJECT_ROOT}/extern/zenoh-c"
NATIVE_ANDROID_DIR="${PROJECT_ROOT}/package/native/android"
API_LEVEL="${API_LEVEL:-24}"

# Default ABIs
ABIS=("arm64-v8a" "x86_64")

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --abi) ABIS=("$2"); shift 2 ;;
    --api) API_LEVEL="$2"; shift 2 ;;
    --all) ABIS=("arm64-v8a" "x86_64" "armeabi-v7a" "x86"); shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect ANDROID_NDK_HOME if not set
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  NDK_BASE="${HOME}/Android/Sdk/ndk"
  if [[ -d "${NDK_BASE}" ]]; then
    # Pick the highest version directory
    ANDROID_NDK_HOME=$(find "${NDK_BASE}" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)
    export ANDROID_NDK_HOME
    echo "Auto-detected ANDROID_NDK_HOME: ${ANDROID_NDK_HOME}"
  else
    echo "Error: ANDROID_NDK_HOME not set and no NDK found at ${NDK_BASE}"
    exit 1
  fi
fi

# Prerequisites check
command -v cargo >/dev/null 2>&1 || { echo "Error: cargo not found"; exit 1; }
command -v cargo-ndk >/dev/null 2>&1 || {
  echo "cargo-ndk not found. Install with: cargo install cargo-ndk"
  exit 1
}

if [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
  echo "Error: ANDROID_NDK_HOME does not exist: ${ANDROID_NDK_HOME}"
  exit 1
fi

# Ensure required Rust targets are installed
declare -A ABI_TO_TARGET=(
  ["arm64-v8a"]="aarch64-linux-android"
  ["armeabi-v7a"]="armv7-linux-androideabi"
  ["x86"]="i686-linux-android"
  ["x86_64"]="x86_64-linux-android"
)

for abi in "${ABIS[@]}"; do
  target="${ABI_TO_TARGET[$abi]}"
  echo "Ensuring Rust target: ${target}"
  rustup target add "${target}"
done

# Build zenoh-c for each ABI, outputting directly to package/native/android/
# cargo-ndk requires running from the crate directory (--manifest-path is not
# well supported by cargo-ndk's internal cargo metadata invocation).
cd "${ZENOHC_DIR}"

for abi in "${ABIS[@]}"; do
  echo "Building zenoh-c for ${abi} (API level ${API_LEVEL})..."
  mkdir -p "${NATIVE_ANDROID_DIR}/${abi}"

  RUSTUP_TOOLCHAIN=stable cargo ndk \
    -t "${abi}" \
    --platform "${API_LEVEL}" \
    -o "${NATIVE_ANDROID_DIR}" \
    build --release

  echo "Built: ${NATIVE_ANDROID_DIR}/${abi}/libzenohc.so"
done

# --- C shim cross-compilation ---
# Build libzenoh_dart.so for each ABI using CMake with the NDK toolchain.
# src/CMakeLists.txt discovers libzenohc.so from package/native/android/<abi>/.

command -v cmake >/dev/null 2>&1 || { echo "Error: cmake not found"; exit 1; }
command -v ninja >/dev/null 2>&1 || { echo "Error: ninja not found"; exit 1; }

cd "${PROJECT_ROOT}"

for abi in "${ABIS[@]}"; do
  echo "Building C shim for ${abi}..."

  BUILD_DIR="${PROJECT_ROOT}/build/android/${abi}"
  cmake \
    -S "${PROJECT_ROOT}/src" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${abi}" \
    -DANDROID_PLATFORM="android-${API_LEVEL}" \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build "${BUILD_DIR}" --config Release

  cp "${BUILD_DIR}/libzenoh_dart.so" "${NATIVE_ANDROID_DIR}/${abi}/"
  echo "Built: ${NATIVE_ANDROID_DIR}/${abi}/libzenoh_dart.so"
done

echo ""
echo "Done. Android prebuilts at: ${NATIVE_ANDROID_DIR}"
ls -la "${NATIVE_ANDROID_DIR}"/*/lib*.so
