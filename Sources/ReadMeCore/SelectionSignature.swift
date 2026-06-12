import Foundation

// Cheap identity for a selection: first and last few words plus the total
// length. Comparing signatures on resume detects that the user selected
// something new without hashing the whole text.
public enum SelectionSignature {
    public static func make(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let head = words.prefix(6).joined(separator: " ")
        let tail = words.suffix(6).joined(separator: " ")
        return "\(head)|\(text.count)|\(tail)".lowercased()
    }
}
