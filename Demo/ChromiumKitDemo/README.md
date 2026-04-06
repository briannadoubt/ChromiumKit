# ChromiumKit Demo

This is a runnable local macOS demo app for the package in the repository root.

Generate the Xcode project:

```bash
cd Demo/ChromiumKitDemo
xcodegen generate
```

`xcodegen generate` also runs ChromiumKit's managed integration step, so the generated project uses `ChromiumKitHostSupport/` just like a normal consumer app.

Build the app:

```bash
xcodebuild \
  -project ChromiumKitDemo.xcodeproj \
  -scheme ChromiumKitDemo \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Launch the built app:

```bash
open ~/Library/Developer/Xcode/DerivedData/ChromiumKitDemo-*/Build/Products/Debug/ChromiumKitDemo.app
```
