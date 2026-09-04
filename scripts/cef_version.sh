#!/usr/bin/env bash

set -euo pipefail

readonly CEF_VERSION="151.3.24+g2384915+chromium-151.0.7922.174"
readonly CEF_DOWNLOAD_BASE_URL="https://cef-builds.spotifycdn.com"
readonly CEF_ARM64_ARCHIVE="cef_binary_${CEF_VERSION}_macosarm64_minimal.tar.bz2"
readonly CEF_X64_ARCHIVE="cef_binary_${CEF_VERSION}_macosx64_minimal.tar.bz2"
