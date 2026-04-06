import SwiftUI
import ChromiumKit

@main
struct MinimalBrowserApp: App {
    init() {
        try? ChromiumRuntime.configure { configuration in
            configuration.additionalArguments = [
                "--disable-gpu-shader-disk-cache"
            ]
        }
    }

    var body: some Scene {
        WindowGroup("ChromiumKit Minimal") {
            ContentView()
        }
    }
}
