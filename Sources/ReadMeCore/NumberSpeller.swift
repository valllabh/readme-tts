import Foundation

// Converts numeric tokens into spoken words. Marvis was trained on speech
// transcripts where numbers appear as words, so digit strings are a major
// hallucination source and get expanded client side.
enum NumberSpeller {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func cardinal(_ n: Int) -> String {
        let words = formatter.string(from: NSNumber(value: n)) ?? String(n)
        return words.replacingOccurrences(of: "-", with: " ")
    }

    static func digits(_ s: String) -> String {
        s.compactMap { c -> String? in
            guard let d = c.wholeNumberValue else { return nil }
            return cardinal(d)
        }.joined(separator: " ")
    }

    // Years read in pairs: 1984 is nineteen eighty four, 2026 is twenty
    // twenty six, 2005 is two thousand five.
    static func year(_ n: Int) -> String {
        guard (1100 ... 2099).contains(n) else { return cardinal(n) }
        if (2000 ... 2009).contains(n) {
            return n == 2000 ? "two thousand" : "two thousand " + cardinal(n - 2000)
        }
        let head = n / 100
        let tail = n % 100
        if tail == 0 {
            return cardinal(head) + " hundred"
        }
        if tail < 10 {
            return cardinal(head) + " oh " + cardinal(tail)
        }
        return cardinal(head) + " " + cardinal(tail)
    }

    static func ordinal(_ n: Int) -> String {
        var words = cardinal(n)
        let irregular: [String: String] = [
            "one": "first", "two": "second", "three": "third", "five": "fifth",
            "eight": "eighth", "nine": "ninth", "twelve": "twelfth",
        ]
        var parts = words.components(separatedBy: " ")
        guard let last = parts.last else { return words }
        if let replacement = irregular[last] {
            parts[parts.count - 1] = replacement
        } else if last.hasSuffix("y") {
            parts[parts.count - 1] = String(last.dropLast()) + "ieth"
        } else {
            parts[parts.count - 1] = last + "th"
        }
        words = parts.joined(separator: " ")
        return words
    }

    // 9:05 pm reads nine oh five p m, 14:00 reads fourteen hundred.
    static func time(hour: Int, minute: Int, suffix: String?) -> String {
        var result = cardinal(hour)
        if minute == 0 {
            result += suffix == nil ? " hundred" : ""
        } else if minute < 10 {
            result += " oh " + cardinal(minute)
        } else {
            result += " " + cardinal(minute)
        }
        if let suffix {
            result += " " + suffix.lowercased().map(String.init).joined(separator: " ")
        }
        return result
    }
}
