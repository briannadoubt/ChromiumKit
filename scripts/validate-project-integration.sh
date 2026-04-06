#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
PROJECT_COPY_DIR="${TMP_DIR}/ChromiumKitDemo"
PROJECT_PATH="${PROJECT_COPY_DIR}/ChromiumKitDemo.xcodeproj"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

cp -R "${ROOT_DIR}/Demo/ChromiumKitDemo" "${PROJECT_COPY_DIR}"

INTEGRATE_OUTPUT="$(cd "${ROOT_DIR}" && swift run chromiumkit integrate --project "${PROJECT_PATH}" --target ChromiumKitDemo)"
DOCTOR_OUTPUT="$(cd "${ROOT_DIR}" && swift run chromiumkit doctor --project "${PROJECT_PATH}" --target ChromiumKitDemo)"

echo "${INTEGRATE_OUTPUT}"
echo "${DOCTOR_OUTPUT}"

grep -q "Integrated ChromiumKit into ChromiumKitDemo.xcodeproj for target ChromiumKitDemo" <<< "${INTEGRATE_OUTPUT}"
grep -q "Managed host support:" <<< "${INTEGRATE_OUTPUT}"
grep -q "Resolved app target 'ChromiumKitDemo' for project integration." <<< "${DOCTOR_OUTPUT}"
grep -q "Found managed ChromiumKit host support directory." <<< "${DOCTOR_OUTPUT}"
grep -q "Found managed embed_cef.sh script." <<< "${DOCTOR_OUTPUT}"
grep -q "The app target uses the managed ChromiumKit build phase." <<< "${DOCTOR_OUTPUT}"
