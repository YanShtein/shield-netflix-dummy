#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

trap adb_cleanup EXIT

require_tools adb javac d8 aapt2 jar zipalign keytool apksigner

BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
KEYSTORE_FULL_PATH="${ROOT_DIR}/${KEYSTORE_PATH}"

mkdir -p "${BUILD_DIR}"/{stub_classes,classes} "${DIST_DIR}" "$(dirname "${KEYSTORE_FULL_PATH}")"

if [[ ! -f "${BUILD_DIR}/framework-res.apk" ]]; then
  adb_connect_verified
  echo "[build] Pulling /system/framework/framework-res.apk from Shield..."
  adb -s "${TARGET}" pull /system/framework/framework-res.apk "${BUILD_DIR}/framework-res.apk" >/dev/null
fi

echo "[build] Compiling Java stubs and MainActivity..."
javac -Xlint:-options --release "${JAVA_RELEASE}" -d "${BUILD_DIR}/stub_classes" \
  "${ROOT_DIR}/stubs/android/os/Bundle.java" \
  "${ROOT_DIR}/stubs/android/app/Activity.java"

javac -Xlint:-options --release "${JAVA_RELEASE}" -cp "${BUILD_DIR}/stub_classes" -d "${BUILD_DIR}/classes" \
  "${ROOT_DIR}/src/com/netflix/ninja/MainActivity.java"

echo "[build] Converting bytecode to DEX and linking resources..."
d8 --min-api "${MIN_SDK}" --lib "${BUILD_DIR}/stub_classes" --output "${BUILD_DIR}/" \
  "${BUILD_DIR}/classes/com/netflix/ninja/MainActivity.class"

aapt2 link -o "${BUILD_DIR}/unaligned.apk" \
  -I "${BUILD_DIR}/framework-res.apk" \
  --manifest "${ROOT_DIR}/AndroidManifest.xml" \
  --min-sdk-version "${MIN_SDK}" \
  --target-sdk-version "${TARGET_SDK}" \
  --version-code "${VERSION_CODE}" \
  --version-name "${VERSION_NAME}"

jar uf "${BUILD_DIR}/unaligned.apk" -C "${BUILD_DIR}" classes.dex
zipalign -f -p 4 "${BUILD_DIR}/unaligned.apk" "${BUILD_DIR}/aligned.apk"

if [[ ! -f "${KEYSTORE_FULL_PATH}" ]]; then
  echo "[build] Generating local signing keystore at ${KEYSTORE_PATH}..."
  keytool -genkeypair -noprompt -keystore "${KEYSTORE_FULL_PATH}" \
    -storepass "${KEYSTORE_PASS}" -alias "${KEY_ALIAS}" -keypass "${KEYSTORE_PASS}" \
    -keyalg "${KEY_ALG}" -keysize "${KEY_SIZE}" -validity "${KEY_VALIDITY_DAYS}" \
    -dname "${KEY_DN}" >/dev/null 2>&1
fi

echo "[build] Signing and verifying APK..."
apksigner "${APKSIGNER_JVM_OPT}" sign \
  --ks "${KEYSTORE_FULL_PATH}" \
  --ks-pass "pass:${KEYSTORE_PASS}" \
  --key-pass "pass:${KEYSTORE_PASS}" \
  --out "${APK_PATH}" \
  "${BUILD_DIR}/aligned.apk"

apksigner "${APKSIGNER_JVM_OPT}" verify "${APK_PATH}"
echo "[build] Built ${APK_PATH}"
