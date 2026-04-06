#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT_DIR}/scripts/cef_version.sh"

"${ROOT_DIR}/scripts/fetch_cef.sh"

CACHE_DIR="${ROOT_DIR}/.cache"
EXTRACT_DIR="${CACHE_DIR}/cef"
UNIVERSAL_DIR="${CACHE_DIR}/universal"
ARTIFACT_DIR="${ROOT_DIR}/Artifacts/ChromiumEmbeddedFramework.xcframework"
HELPER_BUILD_DIR="${CACHE_DIR}/helper-build"
HELPER_TEMPLATE_DIR="${ROOT_DIR}/Sources/ChromiumKitTooling/Resources/ChromiumKitHostSupportTemplate"
HELPER_TEMPLATE_APP="${HELPER_TEMPLATE_DIR}/ChromiumKitHelper.app"
HELPER_PROJECT_DIR="${ROOT_DIR}/Support/ChromiumKitHelperBuilder"
HELPER_PROJECT="${HELPER_PROJECT_DIR}/ChromiumKitHelperBuilder.xcodeproj"
RELEASE_TAG="cef-${CEF_VERSION}"
RELEASE_TAG_URLENCODED="${RELEASE_TAG//+/%2B}"

resolve_github_repository_name() {
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        echo "${GITHUB_REPOSITORY}"
        return
    fi

    if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local remote_url
        remote_url="$(git -C "${ROOT_DIR}" config --get remote.origin.url || true)"
        remote_url="${remote_url%.git}"

        case "${remote_url}" in
            git@github.com:*)
                echo "${remote_url#git@github.com:}"
                return
                ;;
            https://github.com/*)
                echo "${remote_url#https://github.com/}"
                return
                ;;
        esac
    fi

    echo "chromiumkit/chromiumkit"
}

GITHUB_REPOSITORY_NAME="$(resolve_github_repository_name)"
RELEASE_URL="https://github.com/${GITHUB_REPOSITORY_NAME}/releases/download/${RELEASE_TAG_URLENCODED}/ChromiumEmbeddedFramework.xcframework.zip"

ARM64_DIST="${EXTRACT_DIR}/arm64/cef_binary_${CEF_VERSION}_macosarm64_minimal"
X64_DIST="${EXTRACT_DIR}/x64/cef_binary_${CEF_VERSION}_macosx64_minimal"
ARM64_FRAMEWORK="${ARM64_DIST}/Release/Chromium Embedded Framework.framework"
X64_FRAMEWORK="${X64_DIST}/Release/Chromium Embedded Framework.framework"
UNIVERSAL_FRAMEWORK="${UNIVERSAL_DIR}/Chromium Embedded Framework.framework"

mkdir -p "${EXTRACT_DIR}/arm64" "${EXTRACT_DIR}/x64" "${UNIVERSAL_DIR}"

if [[ ! -d "${ARM64_DIST}" ]]; then
    echo "Extracting arm64 distribution"
    tar -xjf "${ROOT_DIR}/downloads/${CEF_ARM64_ARCHIVE}" -C "${EXTRACT_DIR}/arm64"
fi

if [[ ! -d "${X64_DIST}" ]]; then
    echo "Extracting x86_64 distribution"
    tar -xjf "${ROOT_DIR}/downloads/${CEF_X64_ARCHIVE}" -C "${EXTRACT_DIR}/x64"
fi

rm -rf "${ROOT_DIR}/Vendor/CEF/include" "${ROOT_DIR}/Vendor/CEF/libcef_dll"
ditto "${ARM64_DIST}/include" "${ROOT_DIR}/Vendor/CEF/include"
ditto "${ARM64_DIST}/libcef_dll" "${ROOT_DIR}/Vendor/CEF/libcef_dll"

rm -rf "${UNIVERSAL_FRAMEWORK}"
ditto "${ARM64_FRAMEWORK}" "${UNIVERSAL_FRAMEWORK}"

if [[ -f "${UNIVERSAL_FRAMEWORK}/Resources/Info.plist" ]]; then
    cp "${UNIVERSAL_FRAMEWORK}/Resources/Info.plist" "${UNIVERSAL_FRAMEWORK}/Info.plist"
fi

lipo -create \
    "${ARM64_FRAMEWORK}/Chromium Embedded Framework" \
    "${X64_FRAMEWORK}/Chromium Embedded Framework" \
    -output "${UNIVERSAL_FRAMEWORK}/Chromium Embedded Framework"

rm -rf "${ARTIFACT_DIR}"
xcodebuild -create-xcframework \
    -framework "${UNIVERSAL_FRAMEWORK}" \
    -output "${ARTIFACT_DIR}" \
    >/dev/null

echo "Built ${ARTIFACT_DIR}"
lipo -info "${ARTIFACT_DIR}/macos-arm64_x86_64/Chromium Embedded Framework.framework/Chromium Embedded Framework"

echo "Building bundled ChromiumKitHelper.app template"
rm -rf "${HELPER_BUILD_DIR}"
xcodegen generate --spec "${HELPER_PROJECT_DIR}/project.yml" --project "${HELPER_PROJECT_DIR}" >/dev/null
xcodebuild \
    -project "${HELPER_PROJECT}" \
    -target ChromiumKitHelper \
    -configuration Debug \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    SYMROOT="${HELPER_BUILD_DIR}" \
    build \
    >/dev/null

rm -rf "${HELPER_TEMPLATE_APP}"
ditto "${HELPER_BUILD_DIR}/Debug/ChromiumKitHelper.app" "${HELPER_TEMPLATE_APP}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.chromiumkit.helper" "${HELPER_TEMPLATE_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ChromiumKitHelper" "${HELPER_TEMPLATE_APP}/Contents/Info.plist"
chmod +x "${HELPER_TEMPLATE_APP}/Contents/MacOS/ChromiumKitHelper"

echo "Preparing release archive metadata"
(cd "${ROOT_DIR}" && swift run chromiumkit prepare-release \
    --package-root "${ROOT_DIR}" \
    --release-url "${RELEASE_URL}") >/dev/null

echo "Updated ${HELPER_TEMPLATE_APP}"
echo "Prepared Dist/ChromiumEmbeddedFramework.xcframework.zip and refreshed Config/cef-artifact-release.json"
