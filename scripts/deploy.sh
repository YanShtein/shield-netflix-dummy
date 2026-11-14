#!/usr/bin/env bash
set -euo pipefail

MODE="install"
PROMPT_LOCKDOWN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      MODE="check"
      shift
      ;;
    --audit-only)
      MODE="audit"
      shift
      ;;
    --no-prompt)
      PROMPT_LOCKDOWN=0
      shift
      ;;
    *)
      break
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

trap adb_cleanup EXIT

require_tools adb

check_target_compatibility() {
  local model device sdk display_id pkg_path
  local supported_list="mdarcy sif darcy foster"

  echo "[check] Querying target device properties..."
  model="$(adb -s "${TARGET}" shell getprop ro.product.model | tr -d '\r')"
  device="$(adb -s "${TARGET}" shell getprop ro.product.device | tr -d '\r')"
  sdk="$(adb -s "${TARGET}" shell getprop ro.build.version.sdk | tr -d '\r')"
  display_id="$(adb -s "${TARGET}" shell getprop ro.build.display.id | tr -d '\r')"

  echo "[check] Target device: ${model} (${device}), Android SDK ${sdk} (${display_id})"

  case " ${supported_list} " in
    *" ${device} "*)
      echo "[check] Device codename '${device}' is supported."
      ;;
    *)
      echo "[warning] Device codename '${device}' is not in the officially tested list (${supported_list// /, }). Proceeding anyway..."
      ;;
  esac

  pkg_path="$(adb -s "${TARGET}" shell pm path "${TARGET_PKG}" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "${pkg_path}" && "${pkg_path}" =~ ^package:/(system|vendor|product)/ ]]; then
    echo "[error] Package ${TARGET_PKG} is preinstalled on a read-only system partition (${pkg_path#package:})." >&2
    echo "        A self-signed dummy APK cannot replace it." >&2
    echo "        To disable the system package instead, run:" >&2
    echo "          adb -s ${TARGET} shell pm disable-user --user 0 ${TARGET_PKG}" >&2
    exit 1
  fi
}

adb_connect_verified

check_target_compatibility

if [[ "${MODE}" == "install" ]]; then
  if [[ ! -f "${APK_PATH}" ]]; then
    echo "Error: ${APK_PATH} not found. Run 'make build' first." >&2
    exit 1
  fi

  echo "[deploy] Removing any existing ${TARGET_PKG} package..."
  adb -s "${TARGET}" uninstall "${TARGET_PKG}" >/dev/null 2>&1 || true

  echo "[deploy] Sideloading ${APK_PATH}..."
  adb -s "${TARGET}" install --no-incremental "${APK_PATH}"
fi

if [[ "${MODE}" != "check" ]]; then
  echo "[audit] Package metadata & granted permissions:"
  adb -s "${TARGET}" shell dumpsys package "${TARGET_PKG}" | grep -E "versionCode|signatures|granted=true" || true

  echo "[audit] AppOps & active process check:"
  adb -s "${TARGET}" shell cmd appops get "${TARGET_PKG}"
  adb -s "${TARGET}" shell pidof "${TARGET_PKG}" || echo "No active PID (expected)"
fi

if is_adb_port_open; then
  echo ""
  echo "[security] WARNING: Network debugging is still OPEN on ${TARGET}."
  echo "           On your Shield, go to:"
  echo "             Settings -> Device Preferences -> Developer options"
  echo "           and switch 'Network debugging' and 'Developer options' OFF."

  if [[ "${PROMPT_LOCKDOWN}" -eq 1 && -t 0 ]]; then
    while is_adb_port_open; do
      echo ""
      read -r -p "Press [Enter] once disabled to verify ${TARGET} is closed (or type 'skip'): " reply
      if [[ "${reply,,}" == "skip" ]]; then
        echo "[security] Skipped port check. Remember to disable Network debugging manually."
        break
      fi
      if ! is_adb_port_open; then
        echo "[security] Verified: ${TARGET} is closed."
        break
      fi
      echo "[security] ${TARGET} is STILL OPEN. Toggle Network debugging OFF on the Shield and try again."
    done
  fi
else
  echo "[security] Verified: ${TARGET} is closed."
fi
