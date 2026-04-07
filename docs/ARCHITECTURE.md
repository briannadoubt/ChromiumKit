# ChromiumKit Architecture

ChromiumKit has four major layers:

## 1. Public Swift API

Location:

- `Sources/ChromiumKit`

Responsibilities:

- expose `WebView`, `WebPage`, `WebProfile`, and runtime-facing types
- keep the API SwiftUI-first and WebKit-like
- translate lower-level bridge callbacks into `@Observable` state on the main
  actor

Design rule:

- raw CEF types should not leak into the stable public surface

## 2. Objective-C++ Bridge

Location:

- `Sources/ChromiumKitBridge`

Responsibilities:

- host the CEF client, browser, handler, and runtime bootstrapping glue
- bridge AppKit lifecycle requirements into the Swift-facing package
- isolate C++ and Objective-C++ implementation details from the Swift module

Design rule:

- bridge code can be lower-level and CEF-specific, but it should stay narrow and
  avoid becoming the public API

## 3. Tooling And Host Integration

Location:

- `Sources/ChromiumKitTooling`
- `Sources/ChromiumKitCLI`
- `Plugins`

Responsibilities:

- generate and refresh `ChromiumKitHostSupport/`
- patch `.xcodeproj` files idempotently
- diagnose project wiring, built app bundles, and release readiness
- support Xcode command plugins and CLI fallback flows

Design rule:

- end developers should not have to hand-author helper targets or bundle
  packaging scripts

## 4. CEF Artifact Pipeline

Location:

- `scripts/build_cef_artifact.sh`
- `scripts/fetch_cef.sh`
- `scripts/cef_version.sh`
- `.github/workflows/update-cef.yml`
- `.github/workflows/release-artifact.yml`

Responsibilities:

- pin the current stable macOS minimal CEF distribution
- build a universal XCFramework from upstream arm64 and x86_64 binaries
- refresh upstream notice files under `Licenses/`
- publish the release asset used by the SwiftPM binary target

Design rule:

- the shipped artifact, metadata, and third-party notices should always move
  together

## Runtime Model

ChromiumKit currently targets the standard CEF windowed model on macOS:

- lazy startup through `ChromiumRuntime`
- `external_message_pump`
- helper app variants for `Renderer`, `GPU`, `Plugin`, and `Alerts`
- final app-bundle mutation via managed host support

This intentionally favors reliability for real macOS apps over a purely
package-only install story.

## Public Release Constraints

Known intentional constraints today:

- macOS 26+ only
- Xcode 26+ only
- standard signed macOS apps are the target
- App Sandbox and Mac App Store hardening are not complete
- downloads, DevTools UI, and popup/window management are still deferred
