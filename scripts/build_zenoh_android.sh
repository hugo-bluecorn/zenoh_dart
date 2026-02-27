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
JNILIBS_DIR="${PROJECT_ROOT}/android/src/main/jniLibs"
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

# Build for each ABI
# cargo-ndk requires running from the crate directory (--manifest-path is not
# well supported by cargo-ndk's internal cargo metadata invocation).
cd "${ZENOHC_DIR}"

for abi in "${ABIS[@]}"; do
  echo "Building zenoh-c for ${abi} (API level ${API_LEVEL})..."
  mkdir -p "${JNILIBS_DIR}/${abi}"

  RUSTUP_TOOLCHAIN=stable cargo ndk \
    -t "${abi}" \
    --platform "${API_LEVEL}" \
    -o "${JNILIBS_DIR}" \
    build --release

  echo "Built: ${JNILIBS_DIR}/${abi}/libzenohc.so"
done

echo ""
echo "Done. Android prebuilts at: ${JNILIBS_DIR}"
ls -la "${JNILIBS_DIR}"/*/libzenohc.so
