import AppKit

// Handles the "Read with ReadMe" entry in the right click Services menu.
// Only active when running from the app bundle, where Info.plist declares
// the NSServices entry.
final class ServicesProvider: NSObject {
    private let speech: SpeechController

    init(speech: SpeechController) {
        self.speech = speech
    }

    @objc func readSelectedText(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error.pointee = "No text selected" as NSString
            return
        }
        DispatchQueue.main.async { [speech] in
            speech.read(text)
        }
    }
}
