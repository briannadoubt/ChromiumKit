#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
HELPER_NAME="ChromiumKitHelper"
CEF_FRAMEWORK_NAME="Chromium Embedded Framework"
CEF_SOURCE_FRAMEWORK="${BUILT_PRODUCTS_DIR}/$CEF_FRAMEWORK_NAME.framework"
CEF_DESTINATION_FRAMEWORK="$FRAMEWORKS_DIR/$CEF_FRAMEWORK_NAME.framework"
HELPER_TEMPLATE_APP="$SCRIPT_DIR/$HELPER_NAME.app"
HELPER_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER}.chromiumkit.helper"

fail() {
  echo "error: ChromiumKit: $1" >&2
  exit 1
}

codesign_identity() {
  if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s' "$EXPANDED_CODE_SIGN_IDENTITY"
  else
    printf '%s' "-"
  fi
}

sign_bundle() {
  local bundle_path="$1"
  /usr/bin/codesign \
    --force \
    --sign "$(codesign_identity)" \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements \
    "$bundle_path"
}

normalize_framework_bundle() {
  local framework_path="$1"
  local framework_name
  framework_name="$(basename "$framework_path" .framework)"
  local versions_dir="$framework_path/Versions"
  local version_a_dir="$versions_dir/A"

  mkdir -p "$version_a_dir"

  for entry in "$framework_name" Resources Libraries; do
    if [[ -e "$framework_path/$entry" && ! -L "$framework_path/$entry" ]]; then
      mv "$framework_path/$entry" "$version_a_dir/$entry"
    fi
  done

  rm -rf "$framework_path/$framework_name" \
         "$framework_path/Resources" \
         "$framework_path/Libraries"
  rm -f "$framework_path/Info.plist"
  ln -sfn "A" "$versions_dir/Current"
  ln -sfn "Versions/Current/$framework_name" "$framework_path/$framework_name"
  ln -sfn "Versions/Current/Resources" "$framework_path/Resources"
  ln -sfn "Versions/Current/Libraries" "$framework_path/Libraries"
}

create_helper_variant() {
  local source_app="$1"
  local variant_name="$2"
  local bundle_identifier="$3"
  local variant_app="$FRAMEWORKS_DIR/$variant_name.app"
  local plist_path="$variant_app/Contents/Info.plist"
  local macos_dir="$variant_app/Contents/MacOS"
  local base_executable="$macos_dir/$HELPER_NAME"
  local variant_executable="$macos_dir/$variant_name"

  rm -rf "$variant_app"
  ditto "$source_app" "$variant_app"
  mv "$base_executable" "$variant_executable"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $variant_name" "$plist_path"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $variant_name" "$plist_path"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_identifier" "$plist_path"
  sign_bundle "$variant_app"
}

[[ -d "$CEF_SOURCE_FRAMEWORK" ]] || fail "Missing $CEF_FRAMEWORK_NAME.framework in BUILT_PRODUCTS_DIR. Make sure the ChromiumKit package product is linked into the app target."
[[ -d "$HELPER_TEMPLATE_APP" ]] || fail "Missing $HELPER_NAME.app in ChromiumKitHostSupport. Re-run 'Integrate ChromiumKit' or 'Repair ChromiumKit'."
[[ -x "$HELPER_TEMPLATE_APP/Contents/MacOS/$HELPER_NAME" ]] || fail "The managed helper executable is missing or not executable at $HELPER_TEMPLATE_APP/Contents/MacOS/$HELPER_NAME."

mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$CEF_DESTINATION_FRAMEWORK"
ditto "$CEF_SOURCE_FRAMEWORK" "$CEF_DESTINATION_FRAMEWORK"
normalize_framework_bundle "$CEF_DESTINATION_FRAMEWORK"
sign_bundle "$CEF_DESTINATION_FRAMEWORK"

BASE_HELPER_APP="$FRAMEWORKS_DIR/$HELPER_NAME.app"
rm -rf "$BASE_HELPER_APP"
ditto "$HELPER_TEMPLATE_APP" "$BASE_HELPER_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $HELPER_BUNDLE_ID" "$BASE_HELPER_APP/Contents/Info.plist"
sign_bundle "$BASE_HELPER_APP"

create_helper_variant "$BASE_HELPER_APP" "$HELPER_NAME (Renderer)" "$HELPER_BUNDLE_ID.renderer"
create_helper_variant "$BASE_HELPER_APP" "$HELPER_NAME (GPU)" "$HELPER_BUNDLE_ID.gpu"
create_helper_variant "$BASE_HELPER_APP" "$HELPER_NAME (Plugin)" "$HELPER_BUNDLE_ID.plugin"
create_helper_variant "$BASE_HELPER_APP" "$HELPER_NAME (Alerts)" "$HELPER_BUNDLE_ID.alerts"
