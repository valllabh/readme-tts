import Foundation

public enum EngineKind: String, CaseIterable {
    case marvis

    public var displayName: String {
        switch self {
        case .marvis: return "Marvis"
        }
    }

    public var modelRepo: String {
        switch self {
        case .marvis: return "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
        }
    }

    public var modelType: String {
        switch self {
        case .marvis: return "csm"
        }
    }

    public var defaultVoice: String? {
        switch self {
        case .marvis: return "conversational_a"
        }
    }

    // Gender labels verified by pitch analysis of the reference audio:
    // conversational_a sits around 182 Hz, conversational_b around 124 Hz.
    public var voices: [(id: String, name: String)] {
        switch self {
        case .marvis:
            return [
                ("conversational_a", "Ava (Female)"),
                ("conversational_b", "Leo (Male)"),
            ]
        }
    }
}

// A recorded global shortcut in Carbon terms, stored in UserDefaults.
public struct Shortcut: Equatable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutAction: String, CaseIterable {
    case read
    case pauseResume
    case readOrStop

    public var displayName: String {
        switch self {
        case .read: return "Read Selection"
        case .pauseResume: return "Pause and Resume"
        case .readOrStop: return "Read or Stop (Spoken Content key)"
        }
    }

    // Carbon defaults: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    public var defaultShortcut: Shortcut {
        switch self {
        case .read: return Shortcut(keyCode: 15, modifiers: 256 | 2048)        // Cmd Option R
        case .pauseResume: return Shortcut(keyCode: 35, modifiers: 256 | 2048) // Cmd Option P
        case .readOrStop: return Shortcut(keyCode: 53, modifiers: 2048)        // Option Escape
        }
    }
}

public enum Preferences {
    private static let engineKey = "engine"
    private static let aiScriptKey = "aiScript"
    private static let voiceKey = "voice"

    public static let shortcutsChanged = Notification.Name("ReadMeShortcutsChanged")

    public static var engine: EngineKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: engineKey),
                  let kind = EngineKind(rawValue: raw)
            else { return .marvis }
            return kind
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: engineKey)
        }
    }

    // LLM polish pass over each chunk before speaking. Off by default; the
    // toggle lives in the preferences window.
    public static var aiScriptEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: aiScriptKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: aiScriptKey)
        }
    }

    // Development only: live trace window of everything sent to the TTS and
    // the polish model. Off by default.
    public static var debugMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: "debugMode")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "debugMode")
        }
    }

    public static var voice: String {
        get {
            UserDefaults.standard.string(forKey: voiceKey)
                ?? engine.defaultVoice
                ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: voiceKey)
        }
    }

    public static func shortcut(for action: ShortcutAction) -> Shortcut {
        guard let dict = UserDefaults.standard.dictionary(forKey: "shortcut.\(action.rawValue)"),
              let keyCode = dict["keyCode"] as? Int,
              let modifiers = dict["modifiers"] as? Int
        else { return action.defaultShortcut }
        return Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    public static func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        UserDefaults.standard.set(
            ["keyCode": Int(shortcut.keyCode), "modifiers": Int(shortcut.modifiers)],
            forKey: "shortcut.\(action.rawValue)"
        )
        NotificationCenter.default.post(name: shortcutsChanged, object: nil)
    }
}
