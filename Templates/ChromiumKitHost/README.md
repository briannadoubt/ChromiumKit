# ChromiumKit Host Template

This folder is now a reference/fallback path, not the recommended installation flow.

Preferred setup:

1. Add the `ChromiumKit` package to your macOS app.
2. Run `Integrate ChromiumKit` from Xcode, or:

```bash
swift run chromiumkit integrate --project /path/to/MyApp.xcodeproj --target MyApp
```

That command creates a managed `ChromiumKitHostSupport/` folder next to your `.xcodeproj`, copies the packaged helper app, and patches the app target to run the managed embed step.

Files in this folder:

- `embed_cef.sh` shows the bundle-packaging logic ChromiumKit uses for CEF.
- `ChromiumKitHelper.mm` and `ChromiumKitHelper-Info.plist` are source references for the helper app ChromiumKit ships as a managed bundle.
- `ChromiumKitApplication.m` is a legacy fallback. The package now installs the AppKit/Cef compatibility shim internally, so the normal managed flow does not require a custom `NSPrincipalClass`.
