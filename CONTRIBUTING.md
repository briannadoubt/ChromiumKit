# Contributing

Thanks for your interest in improving ChromiumKit.

ChromiumKit is a SwiftUI-first wrapper around CEF for macOS. The project has
two goals that should stay in tension:

- make Chromium easy to drop into a macOS app
- keep the Swift-facing API clean and stable for app developers

## Before You Start

- Read [README.md](README.md) for the current supported flow and project scope.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) if your change touches the
  bridge, helper packaging, or release pipeline.
- Use [SECURITY.md](SECURITY.md) for security issues. Do not file public issues
  with exploit details.

## Development Setup

Requirements:

- macOS 26+
- Xcode 26+
- Swift 6.2+
- `xcodegen` for helper-builder and demo-project generation

Common commands:

```bash
swift build
./scripts/test-with-cef.sh
./scripts/validate-project-integration.sh
./scripts/validate-bundle-layout.sh
```

Notes:

- Plain `swift test` is not the supported path for this repo because CEF must
  be staged into the test bundle first.
- The demo project under `Demo/ChromiumKitDemo` is useful for smoke testing,
  but the package validation scripts are the baseline gate for changes.

## Pull Request Guidelines

Please try to keep pull requests focused and easy to review.

Good PRs usually include:

- a short problem statement
- the narrowest possible fix
- tests or validation notes
- any packaging or release implications

If your change touches one of these areas, call it out explicitly in the PR
description:

- `Package.swift`
- `Sources/ChromiumKitBridge`
- `Sources/ChromiumKitTooling`
- `.github/workflows`
- `scripts/build_cef_artifact.sh`

## Project Conventions

- The public Swift API should feel closer to WebKit than to raw CEF.
- Do not expose raw CEF types in stable public APIs unless there is a strong
  compatibility reason.
- Prefer additive API changes over source-breaking churn.
- Keep Objective-C++ bridge details private whenever possible.
- Preserve the managed `ChromiumKitHostSupport/` integration model.

## Testing Expectations

Expected validation depends on the change:

- API / state-management changes:
  run `./scripts/test-with-cef.sh`
- Xcode-project integration changes:
  run `./scripts/validate-project-integration.sh`
- helper packaging / runtime doctor changes:
  run `./scripts/validate-bundle-layout.sh`
- CEF artifact or release-pipeline changes:
  run all of the above and note whether you rebuilt the artifact

## Releases And CEF Updates

ChromiumKit tracks the latest stable macOS minimal CEF build through the update
workflow and release scripts. If you are intentionally changing the pinned CEF
version:

```bash
./scripts/build_cef_artifact.sh
swift run chromiumkit prepare-release --package-root . --version <cef-version> --release-url <release-url>
```

The build script also refreshes the checked-in upstream CEF license material
under `Licenses/`.

## Community Expectations

By participating in this project, you agree to follow
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
