import AppKit
import SwiftUI

// The About panel of the main app window: identity, version, and what the
// app is built on. Version comes from the bundle; running the bare debug
// binary has no Info.plist, hence the dev fallback.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "Version \(short) (\(build))"
        case let (short?, nil): return "Version \(short)"
        default: return "Development build"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("ReadMe")
                .font(.largeTitle.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text("Reads selected text aloud with on device text to speech. Nothing leaves this Mac.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 6)
            Text("Marvis TTS and Gemma on Apple MLX, pure Swift.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Check for Updates…") {
                Updater.checkForUpdates()
            }
            .padding(.top, 10)
            Link("github.com/valllabh/readme", destination: URL(string: "https://github.com/valllabh/readme")!)
                .font(.caption)
            Spacer()
            Text("Made by VJ")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
