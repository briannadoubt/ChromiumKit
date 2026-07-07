#!/usr/bin/env bash

set -euo pipefail

readonly CEF_VERSION="149.0.6+g0d0eeb6+chromium-149.0.7827.201"
readonly CEF_DOWNLOAD_BASE_URL="https://cef-builds.spotifycdn.com"
readonly CEF_ARM64_ARCHIVE="cef_binary_${CEF_VERSION}_macosarm64_minimal.tar.bz2"
readonly CEF_X64_ARCHIVE="cef_binary_${CEF_VERSION}_macosx64_minimal.tar.bz2"
