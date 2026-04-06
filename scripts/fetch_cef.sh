#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT_DIR}/scripts/cef_version.sh"

DOWNLOAD_DIR="${ROOT_DIR}/downloads"
mkdir -p "${DOWNLOAD_DIR}"

download_if_missing() {
    local archive_name="$1"
    local destination="${DOWNLOAD_DIR}/${archive_name}"

    if [[ -f "${destination}" ]]; then
        echo "Using cached ${archive_name}"
        return
    fi

    echo "Downloading ${archive_name}"
    curl --fail --location --progress-bar \
        "${CEF_DOWNLOAD_BASE_URL}/${archive_name}" \
        --output "${destination}"
}

download_if_missing "${CEF_ARM64_ARCHIVE}"
download_if_missing "${CEF_X64_ARCHIVE}"

echo "Downloaded CEF ${CEF_VERSION} into ${DOWNLOAD_DIR}"
