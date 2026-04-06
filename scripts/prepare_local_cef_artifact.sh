#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts"
ARTIFACT_PATH="${ARTIFACTS_DIR}/ChromiumEmbeddedFramework.xcframework"
METADATA_PATH="${ROOT_DIR}/Config/cef-artifact-release.json"
DOWNLOAD_DIR="${ROOT_DIR}/.cache/ci-artifacts"

if [[ -d "${ARTIFACT_PATH}" ]]; then
    echo "CEF artifact already available at ${ARTIFACT_PATH}"
    exit 0
fi

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: missing CEF release metadata at ${METADATA_PATH}" >&2
    exit 1
fi

metadata_output="$(
    python3 - "${METADATA_PATH}" <<'PY'
import json
import re
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text())
match = re.match(r"https://github\.com/([^/]+/[^/]+)/releases/download/cef-(.+)/ChromiumEmbeddedFramework\.xcframework\.zip", metadata["url"])
if not match:
    raise SystemExit(f"Unrecognized release URL: {metadata['url']}")
print(match.group(1))
print(metadata["version"])
PY
)"

REPOSITORY="$(printf '%s\n' "${metadata_output}" | sed -n '1p')"
VERSION="$(printf '%s\n' "${metadata_output}" | sed -n '2p')"
TAG="cef-${VERSION}"
ZIP_PATH="${DOWNLOAD_DIR}/ChromiumEmbeddedFramework.xcframework.zip"

mkdir -p "${DOWNLOAD_DIR}" "${ARTIFACTS_DIR}"
rm -f "${ZIP_PATH}"

echo "Downloading ${TAG} from ${REPOSITORY}"
gh release download "${TAG}" \
    --repo "${REPOSITORY}" \
    --pattern "ChromiumEmbeddedFramework.xcframework.zip" \
    --dir "${DOWNLOAD_DIR}" \
    --clobber

rm -rf "${ARTIFACT_PATH}"
ditto -x -k "${ZIP_PATH}" "${ARTIFACTS_DIR}"

if [[ ! -d "${ARTIFACT_PATH}" ]]; then
    echo "error: expected CEF artifact at ${ARTIFACT_PATH} after download" >&2
    exit 1
fi

echo "Prepared local CEF artifact at ${ARTIFACT_PATH}"
