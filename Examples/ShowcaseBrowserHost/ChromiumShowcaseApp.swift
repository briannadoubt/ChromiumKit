import SwiftUI
import ChromiumKit

@main
struct ChromiumShowcaseApp: App {
    init() {
        try? ChromiumRuntime.configure { configuration in
            let supportDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ChromiumShowcase", isDirectory: true)

            configuration.cacheDirectoryURL = supportDirectory
            configuration.logDirectoryURL = supportDirectory?.appendingPathComponent("Logs", isDirectory: true)
        }
    }

    var body: some Scene {
        WindowGroup("ChromiumKit Showcase") {
            BrowserPlayground()
        }
    }
}
