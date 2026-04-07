# Third-Party Notices

ChromiumKit is an independent open source project. ChromiumKit itself is
licensed under the Apache License 2.0. It also redistributes and depends on
third-party software with separate license terms.

## Chromium Embedded Framework (CEF)

ChromiumKit redistributes the official macOS minimal CEF binary distribution in
its pinned XCFramework release assets and uses upstream CEF headers plus
`libcef_dll_wrapper` sources in the package.

Included upstream materials:

- `Licenses/CEF-LICENSE.txt`
- `Licenses/CEF-README.txt`
- `Chromium-CREDITS.html` in the generated release assets

Those files are copied from the pinned upstream CEF distribution during
`./scripts/build_cef_artifact.sh` so the checked-in notices stay aligned with
the shipped binary artifact.

## Chromium And Other Third-Party Components

CEF bundles Chromium and additional third-party components. Upstream CEF's
README states that complete Chromium and third-party licensing information is
available in `CREDITS.html` or via `about:credits` in a CEF-based application.

For ChromiumKit releases, the relevant upstream files are published alongside
the CEF artifact release so downstream users can preserve the same notice set.

## Downstream Application Responsibility

If you redistribute ChromiumKit-based applications, you are responsible for
ensuring that required upstream notices remain available in your own
distribution, documentation, and release materials where applicable.

In practice, that usually means:

- preserving the upstream CEF license terms
- preserving Chromium and third-party attribution material
- not implying endorsement by Apple, Chromium, or the CEF project

## No Affiliation

ChromiumKit is not affiliated with, endorsed by, or sponsored by Apple,
Chromium, Google, or the Chromium Embedded Framework project.
