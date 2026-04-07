# ChromiumKit

> [!WARNING]
> ChromiumKit is currently alpha / early v1 software. The package works, the
> demo app is real, and CI is green, but the public API and packaging flow
> should still be treated as stabilizing.

`ChromiumKit` is a macOS 26+ Swift package that wraps CEF behind a SwiftUI-first API inspired by WebKit and Apple’s new WebKit-for-SwiftUI surface.

ChromiumKit is an independent open source project. It is not affiliated with or
endorsed by Apple, Chromium, Google, or the CEF project.

It gives you:

- `WebView` for SwiftUI
- `@Observable` `WebPage` for loading, navigation state, and JavaScript
- `ChromiumRuntime` for lazy runtime configuration
- a managed `ChromiumKitHostSupport/` install flow for macOS app packaging
- package command plugins plus the `chromiumkit` CLI for integration, diagnostics, and repair
- pinned prebuilt CEF binaries, with support for remote release-hosted artifacts

`ChromiumKit` is designed for "drop Chromium into my Mac app" more than "surface every raw CEF knob". Raw CEF stays in the bridge layer so the Swift API can stay clean and stable.

## Status

Public launch posture:

- latest stable macOS minimal CEF pin
- managed Xcode integration flow
- GitHub Actions CI plus CodeQL
- Apache-2.0 licensed project files
- checked-in third-party notices for redistributed CEF / Chromium materials

Current v1 scope includes:

- standard browser embedding with the Alloy runtime
- lazy runtime bootstrapping with `external_message_pump`
- SwiftUI `WebView` plus observable `WebPage`
- navigation state, title, URL, and loading progress
- async JavaScript evaluation with typed decoding helpers
- custom URL scheme handlers
- permission and navigation decisions
- managed host-app integration, bundle diagnostics, and release-readiness checks

Deliberately deferred for v1:

- popup/window management inside the app
- downloads
- DevTools UI
- off-screen rendering
- App Sandbox and Mac App Store hardening

Known limitations today:

- ChromiumKit is optimized for standard developer-signed macOS apps first.
- App Sandbox and Mac App Store support are not production-ready.
- The package owns a managed bundle-packaging step because CEF on macOS still
  requires nested helper apps and a final app-bundle layout that SwiftPM does
  not install by itself.
- The API is intentionally WebKit-like, but it is not source-compatible with
  Apple's frameworks.

Related docs:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)

## Quick Start

1. Add the package to your macOS app target in Xcode.
2. Run the ChromiumKit package command once:
   - Xcode: run the `Integrate ChromiumKit` package command.
   - CLI fallback: `swift run chromiumkit integrate --project /path/to/MyApp.xcodeproj --target MyApp`
3. Build your app normally.

The integration step creates a managed `ChromiumKitHostSupport/` folder next to your `.xcodeproj` and patches the app target to use it.

What ChromiumKit manages for you:

- `ChromiumKitHostSupport/embed_cef.sh`
- `ChromiumKitHostSupport/ChromiumKitHelper.app`
- the app-target build phase that embeds CEF into `MyApp.app/Contents/Frameworks`
- helper app variants for `Renderer`, `GPU`, `Plugin`, and `Alerts`

You do not need to hand-author a helper target or set a custom `NSPrincipalClass`. ChromiumKit installs the AppKit/Cef compatibility shim internally.

## SwiftUI Usage

```swift
import SwiftUI
import ChromiumKit

struct ContentView: View {
    @State private var page = WebPage(url: URL(string: "https://www.chromium.org")!)

    var body: some View {
        WebView(page)
    }
}
```

If you want to configure Chromium before the first page is created:

```swift
import ChromiumKit

try ChromiumRuntime.configure { configuration in
    configuration.additionalArguments = [
        "--disable-gpu-shader-disk-cache"
    ]
}
```

## Commands

CLI:

- `swift run chromiumkit integrate --project /path/to/MyApp.xcodeproj --target MyApp`
- `swift run chromiumkit doctor --project /path/to/MyApp.xcodeproj --target MyApp`
- `swift run chromiumkit doctor /path/to/MyApp.app`
- `swift run chromiumkit repair --project /path/to/MyApp.xcodeproj --target MyApp`
- `swift run chromiumkit check-runtime /path/to/MyApp.app`
- `swift run chromiumkit new-host --output /path/to/ChromiumKitHostSupport`
- `swift run chromiumkit prepare-release --package-root /path/to/ChromiumKit`

Use `doctor` when you want a project-level or built-app-level report. Use `repair` when the managed host support or build phase drifted.

## Public API

- `WebView`
- `WebPage`
- `WebPage.Configuration`
- `WebProfile`
- `NavigationDecision`
- `PermissionDecision`
- `URLSchemeHandling`
- `NavigationDeciding`
- `ChromiumRuntime`
- `ChromiumDiagnostics`

`WebPage` mirrors WebKit-style usage:

- `load(_:)`
- `loadHTML(_:baseURL:)`
- `load(data:mimeType:characterEncoding:baseURL:)`
- `reload()`
- `stopLoading()`
- `goBack()`
- `goForward()`
- `callJavaScript(_:)`
- `callJavaScript(_:as:)`

Observable state:

- `title`
- `url`
- `isLoading`
- `estimatedProgress`
- `canGoBack`
- `canGoForward`
- `currentNavigationEvent`

## Examples

Example source files live under:

- [Examples/MinimalBrowserHost](Examples/MinimalBrowserHost)
- [Examples/ShowcaseBrowserHost](Examples/ShowcaseBrowserHost)
- [Demo/ChromiumKitDemo](Demo/ChromiumKitDemo)

The demo app is runnable, loads real web content, and now uses the same managed `ChromiumKitHostSupport/` integration flow recommended for downstream apps. The example folders remain source-only so you can drop them into your own app target and signing setup.

## Packaging Model

CEF on macOS still requires final bundle layout like:

```text
MyApp.app/
  Contents/
    Frameworks/
      Chromium Embedded Framework.framework
      ChromiumKitHelper.app
      ChromiumKitHelper (Renderer).app
      ChromiumKitHelper (GPU).app
      ChromiumKitHelper (Plugin).app
      ChromiumKitHelper (Alerts).app
```

ChromiumKit owns that packaging step through the managed host-support folder. End developers should not need to hand-maintain that logic.

Reference templates live under [Templates/ChromiumKitHost](Templates/ChromiumKitHost), but they are now a fallback/reference path rather than the recommended setup flow.

## Tests And CI

Because CEF's framework install name expects an app-style bundle layout, the supported local test entrypoint is the helper script that stages the framework into the SwiftPM test bundle before execution:

```bash
./scripts/test-with-cef.sh
./scripts/validate-bundle-layout.sh
./scripts/validate-project-integration.sh
```

CI configuration lives at [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Dependency Automation

ChromiumKit now uses two automation paths:

- [.github/dependabot.yml](.github/dependabot.yml) keeps GitHub Actions dependencies current.
- [.github/workflows/update-cef.yml](.github/workflows/update-cef.yml) polls the official CEF builds index once per day, tracks the latest stable macOS minimal build only, rebuilds the vendored artifact, refreshes the helper template and release metadata, publishes the new binary release asset, and opens a PR against `main`.

This split exists because Dependabot does not natively understand Chromium/CEF release feeds or our custom `cef_version.sh` plus binary-release workflow.

## CEF Artifact Workflow

Pinned CEF version metadata lives in [scripts/cef_version.sh](scripts/cef_version.sh).

To rebuild the vendored artifact and refresh release metadata:

```bash
./scripts/build_cef_artifact.sh
swift run chromiumkit prepare-release --package-root . --release-url https://github.com/your-org/your-repo/releases/download/cef-<version>/ChromiumEmbeddedFramework.xcframework.zip
```

`Package.swift` prefers the repo-local artifact when it exists. Set `CHROMIUMKIT_USE_LOCAL_CEF_ARTIFACT=0` to validate the remote binary-target path.

Current pin:

- `146.0.10+g8219561+chromium-146.0.7680.179`

## Notes

- The package uses prebuilt official CEF distributions, not a full Chromium source build.
- The bridge layer is Objective-C++ and intentionally private to keep the Swift API stable.
- Standard signed macOS apps are the production target for v1. App Sandbox and Mac App Store hardening are follow-up work.
- See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for open source licensing and redistributed third-party notice information.
