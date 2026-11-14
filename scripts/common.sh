#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${ROOT_DIR}/config.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/config.env"
else
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/config.env.example"
fi

SHIELD_IP="${1:-${SHIELD_IP}}"
SHIELD_PORT="${2:-${SHIELD_PORT}}"
TARGET="${SHIELD_IP}:${SHIELD_PORT}"

# Fixed build & package constants
TARGET_PKG="com.netflix.ninja"
VERSION_CODE="999999"
VERSION_NAME="99.0.0"

JAVA_RELEASE="8"
MIN_SDK="21"
TARGET_SDK="30"
BUILD_TOOLS_APT_PKG="google-android-build-tools-35.0.1-installer"
APKSIGNER_JVM_OPT="-J-enable-native-access=ALL-UNNAMED"

KEYSTORE_PATH="keystore/debug.keystore"
KEYSTORE_PASS="android"
KEY_ALIAS="androiddebugkey"
KEY_ALG="RSA"
KEY_SIZE="2048"
KEY_VALIDITY_DAYS="10000"
KEY_DN="CN=Dummy,O=Local,C=US"

APK_PATH="${ROOT_DIR}/dist/netflix-dummy.apk"

adb_cleanup() {
  adb disconnect "${TARGET}" >/dev/null 2>&1 || true
  adb kill-server >/dev/null 2>&1 || true
}

require_tools() {
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "Error: '${cmd}' not found. Run 'make deps' first." >&2
      exit 1
    fi
  done
}

adb_connect_verified() {
  echo "[adb] Connecting to ${TARGET}..."
  adb connect "${TARGET}" >/dev/null
  if [[ "$(adb -s "${TARGET}" get-state 2>/dev/null || true)" != "device" ]]; then
    echo "Error: ${TARGET} is unreachable or awaiting TV-screen RSA authorization." >&2
    exit 1
  fi
}

is_adb_port_open() {
  timeout 2 bash -c "</dev/tcp/${SHIELD_IP}/${SHIELD_PORT}" >/dev/null 2>&1
}
