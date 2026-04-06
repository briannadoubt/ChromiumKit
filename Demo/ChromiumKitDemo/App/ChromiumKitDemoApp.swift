import SwiftUI
import ChromiumKit

@main
struct ChromiumKitDemoApp: App {
    init() {
        try? ChromiumRuntime.configure { configuration in
            let supportDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ChromiumKitDemo", isDirectory: true)

            configuration.cacheDirectoryURL = supportDirectory
            configuration.logDirectoryURL = supportDirectory?.appendingPathComponent("Logs", isDirectory: true)
            configuration.additionalArguments = [
                "--disable-gpu-shader-disk-cache"
            ]
        }
    }

    var body: some Scene {
        WindowGroup("ChromiumKit Demo") {
            BrowserPlayground()
        }
    }
}
