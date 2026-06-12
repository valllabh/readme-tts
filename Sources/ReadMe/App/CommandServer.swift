import AppKit
import ReadMeCore

// Local message port so the CLI can hand work to the running menu bar app
// instead of loading its own copy of the models. The app is already warm,
// so a CLI speak starts instantly and gets the transport controls for free.
@MainActor
enum CommandServer {
    static let portName = "app.readme.tts.cmd"

    struct Command: Codable {
        var action: String
        var text: String?
    }

    private static var speech: SpeechController?
    private static var port: CFMessagePort?

    static func start(speech controller: SpeechController) {
        speech = controller
        var context = CFMessagePortContext()
        let local = CFMessagePortCreateLocal(
            nil,
            portName as CFString,
            commandPortCallback,
            &context,
            nil
        )
        guard let local else {
            Log.error("command server: port creation failed")
            return
        }
        let source = CFMessagePortCreateRunLoopSource(nil, local, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        port = local
        Log.info("command server: listening on \(portName)")
    }

    static func handle(data: Data?) -> Unmanaged<CFData>? {
        guard let data,
              let command = try? JSONDecoder().decode(Command.self, from: data)
        else {
            return reply("bad request")
        }
        Log.info("command server: \(command.action)")
        switch command.action {
        case "speak":
            guard let text = command.text, !text.isEmpty else {
                return reply("missing text")
            }
            speech?.read(text)
            return reply("ok")
        case "stop":
            speech?.stop()
            return reply("ok")
        default:
            return reply("unknown action")
        }
    }

    static func reply(_ message: String) -> Unmanaged<CFData> {
        .passRetained(Data(message.utf8) as CFData)
    }

    // CLI side: returns true when a running app accepted the command. Pure
    // message port use, no main actor state.
    nonisolated static func send(_ command: Command) -> Bool {
        guard let remote = CFMessagePortCreateRemote(nil, portName as CFString),
              let payload = try? JSONEncoder().encode(command)
        else { return false }
        var responseData: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote,
            0,
            payload as CFData,
            5,
            5,
            CFRunLoopMode.defaultMode.rawValue,
            &responseData
        )
        let response = responseData
            .map { String(decoding: $0.takeRetainedValue() as Data, as: UTF8.self) }
        return status == kCFMessagePortSuccess && response == "ok"
    }
}

// CFMessagePort needs a context free C function pointer; it hops to the main
// actor, where the message port run loop source lives anyway.
private func commandPortCallback(
    _ port: CFMessagePort?,
    _ messageID: Int32,
    _ data: CFData?,
    _ info: UnsafeMutableRawPointer?
) -> Unmanaged<CFData>? {
    MainActor.assumeIsolated {
        CommandServer.handle(data: data.map { $0 as Data })
    }
}
