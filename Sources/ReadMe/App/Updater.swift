import AppKit
import Sparkle

// Sparkle auto updates fed by appcast.xml on the GitHub repo, with release
// zips on GitHub Releases. Updates are EdDSA signed; the private key lives
// only in VJ's keychain (make sparkle-keys), the public key in Info.plist.
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    // Dev builds run as a bare binary with no Info.plist, so there is no
    // feed to check and Sparkle would only log errors. Bundled builds carry
    // SUFeedURL and start checking automatically.
    static func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            Log.info("updater: no SUFeedURL, skipping (unbundled dev build)")
            return
        }
        controller.startUpdater()
        Log.info("updater: started")
    }

    static func checkForUpdates() {
        Log.info("updater: manual check")
        controller.checkForUpdates(nil)
    }
}
