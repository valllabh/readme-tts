import AppKit
import SwiftUI

// The one app window: sidebar with the app identity and panel list on the
// left, the selected panel on the right. Settings and Logs today, more
// panels later. Menu actions land on a specific panel via show(_:).
enum AppPanel: String, CaseIterable, Identifiable {
    case settings
    case logs
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .logs: return "Logs"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .settings: return "gearshape"
        case .logs: return "doc.text"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController {
    static let shared = MainWindowController()

    private let state = MainWindowState()

    private init() {
        let hosting = NSHostingController(rootView: MainWindowView(state: state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "ReadMe"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 880, height: 600))
        window.minSize = NSSize(width: 640, height: 420)
        // Accessory apps open windows on the desktop Space by default, which
        // makes the window invisible when the user is in a fullscreen app or
        // another Space. Join whatever Space is active instead.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show(_ panel: AppPanel) {
        state.panel = panel
        // The app lives as an accessory (menu bar only), which keeps it out
        // of Cmd-Tab. While the window is open, become a regular app so the
        // switcher can reach it; windowWillClose flips it back.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class MainWindowState: ObservableObject {
    @Published var panel: AppPanel = .settings
}

struct MainWindowView: View {
    @ObservedObject var state: MainWindowState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("ReadMe")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 10)

                List(selection: selection) {
                    ForEach(AppPanel.allCases) { panel in
                        Label(panel.title, systemImage: panel.symbol)
                            .tag(panel)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch state.panel {
            case .settings:
                PreferencesView()
            case .logs:
                LogViewerView()
            case .about:
                AboutView()
            }
        }
    }

    // List selection wants an optional; the window always has a panel.
    private var selection: Binding<AppPanel?> {
        Binding(
            get: { state.panel },
            set: { if let panel = $0 { state.panel = panel } }
        )
    }
}
