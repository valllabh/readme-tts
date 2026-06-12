import AppKit

@main
@MainActor
enum ReadMeApp {
    static func main() {
        CLIRunner.prepareConsole()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
