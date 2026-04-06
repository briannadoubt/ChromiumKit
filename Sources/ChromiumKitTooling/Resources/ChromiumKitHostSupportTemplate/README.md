# ChromiumKit Host Support

This folder is managed by ChromiumKit.

It contains the build-time assets ChromiumKit needs to package CEF into your macOS app:

- `embed_cef.sh` copies and signs the CEF framework plus helper app variants
- `ChromiumKitHelper.app` is the base helper bundle copied into the final app
- `ChromiumKitHelper.mm` and `ChromiumKitHelper-Info.plist` are the source templates used to build the helper bundle shipped by ChromiumKit

Re-run `Integrate ChromiumKit` or `Repair ChromiumKit` if these files drift or go missing.
