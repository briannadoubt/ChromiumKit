#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
APP_BUNDLE="${TMP_DIR}/ChromiumKitFixture.app"
FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"

export CHROMIUMKIT_USE_LOCAL_CEF_ARTIFACT=1

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

mkdir -p "${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework"

for helper_name in \
    "ChromiumKitHelper" \
    "ChromiumKitHelper (Renderer)" \
    "ChromiumKitHelper (GPU)" \
    "ChromiumKitHelper (Plugin)" \
    "ChromiumKitHelper (Alerts)"; do
    helper_dir="${FRAMEWORKS_DIR}/${helper_name}.app/Contents/MacOS"
    mkdir -p "${helper_dir}"
    touch "${helper_dir}/${helper_name}"
    chmod +x "${helper_dir}/${helper_name}"
done

OUTPUT="$(cd "${ROOT_DIR}" && swift run chromiumkit doctor "${APP_BUNDLE}")"
echo "${OUTPUT}"

grep -q "Found Chromium Embedded Framework.framework" <<< "${OUTPUT}"
grep -q "Found helper app bundle: ChromiumKitHelper.app" <<< "${OUTPUT}"
grep -q "Found helper executable: ChromiumKitHelper" <<< "${OUTPUT}"
grep -q "Found helper app bundle: ChromiumKitHelper (Renderer).app" <<< "${OUTPUT}"
grep -q "Found helper executable: ChromiumKitHelper (Renderer)" <<< "${OUTPUT}"
grep -q "Found helper app bundle: ChromiumKitHelper (GPU).app" <<< "${OUTPUT}"
grep -q "Found helper executable: ChromiumKitHelper (GPU)" <<< "${OUTPUT}"
grep -q "Found helper app bundle: ChromiumKitHelper (Plugin).app" <<< "${OUTPUT}"
grep -q "Found helper executable: ChromiumKitHelper (Plugin)" <<< "${OUTPUT}"
grep -q "Found helper app bundle: ChromiumKitHelper (Alerts).app" <<< "${OUTPUT}"
grep -q "Found helper executable: ChromiumKitHelper (Alerts)" <<< "${OUTPUT}"
