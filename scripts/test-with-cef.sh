#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK_DIR="${ROOT_DIR}/Artifacts/ChromiumEmbeddedFramework.xcframework/macos-arm64_x86_64"
FRAMEWORK_SOURCE="${FRAMEWORK_DIR}/Chromium Embedded Framework.framework"
FRAMEWORK_BINARY="${FRAMEWORK_SOURCE}/Chromium Embedded Framework"
EXPECTED_INSTALL_NAME="@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework"

export DYLD_FRAMEWORK_PATH="${FRAMEWORK_DIR}${DYLD_FRAMEWORK_PATH:+:${DYLD_FRAMEWORK_PATH}}"
export CHROMIUMKIT_USE_LOCAL_CEF_ARTIFACT=1

cd "${ROOT_DIR}"
swift build --build-tests "$@"

BUILD_DIR="$(find "${ROOT_DIR}/.build" -type d -path '*-apple-macosx/debug' | head -n 1)"
if [[ -z "${BUILD_DIR}" ]]; then
    echo "error: ChromiumKit could not locate the SwiftPM debug build directory." >&2
    exit 1
fi

link_framework() {
    local destination="$1"
    mkdir -p "$(dirname "${destination}")"
    rm -rf "${destination}"
    ln -s "${FRAMEWORK_SOURCE}" "${destination}"
}

link_framework "${BUILD_DIR}/Frameworks/Chromium Embedded Framework.framework"

while IFS= read -r test_bundle; do
    link_framework "${test_bundle}/Contents/Frameworks/Chromium Embedded Framework.framework"
    while IFS= read -r test_binary; do
        if otool -L "${test_binary}" | grep -Fq "${EXPECTED_INSTALL_NAME}"; then
            install_name_tool -change "${EXPECTED_INSTALL_NAME}" "${FRAMEWORK_BINARY}" "${test_binary}"
        fi
    done < <(find "${test_bundle}/Contents/MacOS" -maxdepth 1 -type f)
done < <(find "${BUILD_DIR}" -maxdepth 1 -type d -name '*.xctest')

swift test --skip-build "$@"
