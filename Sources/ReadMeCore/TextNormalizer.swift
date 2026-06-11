import Foundation

// Rewrites screen text into a form that reads naturally aloud. The Marvis
// stack does no normalization of its own (raw text goes straight into the
// LLM tokenizer) and the model was trained on speech transcripts, so digits,
// symbols, markdown, and URLs all need expanding into spoken words here.
// Rule set ported from coqui TTS cleaners, misaki, and NeMo categories.
// Newlines are preserved; SentenceChunker turns them into real pauses.
public enum TextNormalizer {
    public static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")

        // Markdown structure: fences, headings, bullets, quotes.
        s = replace(s, #"```[a-zA-Z0-9]*\n?"#, "")
        s = replace(s, #"`([^`]*)`"#, "$1")
        s = replace(s, #"(?m)^#{1,6}\s+"#, "")
        s = replace(s, #"(?m)^\s*[-*•]\s+"#, "")
        s = replace(s, #"(?m)^\s*>\s+"#, "")

        // Tables: markdown pipe rows and Word style tab rows become comma
        // separated cells ending in a period, so each row reads as its own
        // sentence with a pause. Separator rows disappear.
        s = normalizeTables(s)

        // Markdown links and images: speak the label, drop the URL.
        s = replace(s, #"!\[([^\]]*)\]\([^)]*\)"#, "$1")
        s = replace(s, #"\[([^\]]+)\]\([^)]*\)"#, "$1")
        s = replace(s, #"(\*\*|__)(.+?)\1"#, "$2")
        s = replace(s, #"\*([^*\n]+)\*"#, "$1")

        // Bare URLs: speak the host with dots spoken, drop the path.
        s = replaceMatches(s, #"https?://(?:www\.)?([a-zA-Z0-9.-]+)[^\s]*"#) { groups in
            groups[1].replacingOccurrences(of: ".", with: " dot ")
        }
        // Emails: name at domain, dots spoken.
        s = replaceMatches(s, #"([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)"#) { groups in
            let local = groups[1].replacingOccurrences(of: ".", with: " dot ")
            let host = groups[2].replacingOccurrences(of: ".", with: " dot ")
            return local + " at " + host
        }

        // Times: 9:05pm, 14:30.
        s = replaceMatches(s, #"\b(\d{1,2}):(\d{2})\s*(am|pm|AM|PM)?\b"#) { groups in
            guard let h = Int(groups[1]), let m = Int(groups[2]), h <= 24, m < 60 else {
                return groups[0]
            }
            return NumberSpeller.time(hour: h, minute: m, suffix: groups[3].isEmpty ? nil : groups[3])
        }

        // Currency: $5.50, $3,000.
        s = replaceMatches(s, #"\$\s?([\d,]+)(?:\.(\d{1,2}))?"#) { groups in
            let whole = Int(groups[1].replacingOccurrences(of: ",", with: "")) ?? 0
            let dollars = NumberSpeller.cardinal(whole) + (whole == 1 ? " dollar" : " dollars")
            guard !groups[2].isEmpty, let cents = Int(groups[2]), cents > 0 else { return dollars }
            return dollars + " and " + NumberSpeller.cardinal(cents) + (cents == 1 ? " cent" : " cents")
        }

        // Percent and degrees.
        s = replace(s, #"(\d)\s*%"#, "$1 percent")
        s = replace(s, #"(\d)\s*°"#, "$1 degrees")

        // Units attached to numbers.
        let units: [(String, String)] = [
            ("ms", "milliseconds"), ("kg", "kilograms"), ("km", "kilometers"),
            ("cm", "centimeters"), ("mm", "millimeters"), ("kb", "kilobytes"),
            ("mb", "megabytes"), ("gb", "gigabytes"), ("tb", "terabytes"),
            ("ghz", "gigahertz"), ("mhz", "megahertz"), ("hz", "hertz"),
        ]
        for (unit, spoken) in units {
            s = replace(s, #"(\d)\s*"# + unit + #"\b"#, "$1 \(spoken)", caseInsensitive: true)
        }

        // Ordinals: 3rd, 21st.
        s = replaceMatches(s, #"\b(\d+)(st|nd|rd|th)\b"#) { groups in
            guard let n = Int(groups[1]) else { return groups[0] }
            return NumberSpeller.ordinal(n)
        }

        // Decimals: 3.14.
        s = replaceMatches(s, #"(\d+)\.(\d+)"#) { groups in
            guard let whole = Int(groups[1]) else { return groups[0] }
            return NumberSpeller.cardinal(whole) + " point " + NumberSpeller.digits(groups[2])
        }

        // Thousands separators, then remaining whole numbers.
        s = replace(s, #"(\d),(\d{3})\b"#, "$1$2")
        s = replace(s, #"(\d),(\d{3})\b"#, "$1$2")
        s = replaceMatches(s, #"\b\d+\b"#) { groups in
            let token = groups[0]
            guard let n = Int(token) else { return NumberSpeller.digits(token) }
            if token.count == 4, (1100 ... 2099).contains(n) {
                return NumberSpeller.year(n)
            }
            if token.count >= 5 || token.hasPrefix("0") && token.count > 1 {
                return NumberSpeller.digits(token)
            }
            return NumberSpeller.cardinal(n)
        }

        // Symbols spoken as words.
        s = replace(s, #"\s&\s"#, " and ")
        s = replace(s, #"\s*(->|→|=>|⇒)\s*"#, " to ")
        s = replace(s, #"(\w)\s*\+\s*(\w)"#, "$1 plus $2")
        s = replace(s, #"\s=\s"#, " equals ")
        s = replace(s, #"([a-zA-Z])/([a-zA-Z])"#, "$1 or $2")
        s = replace(s, #"~\s*(?=\w)"#, "about ")
        s = replace(s, #"±"#, "plus or minus")
        s = replace(s, #"×"#, " times ")

        // Abbreviations that models stumble on (coqui list, trimmed).
        let abbreviations: [(String, String)] = [
            (#"\be\.g\.,?\s*"#, "for example, "),
            (#"\bi\.e\.,?\s*"#, "that is, "),
            (#"\betc\.(?=\s|$)"#, "etcetera."),
            (#"\bvs\.?\s"#, "versus "),
            (#"\bMr\.\s"#, "mister "),
            (#"\bMrs\.\s"#, "misses "),
            (#"\bDr\.\s"#, "doctor "),
            (#"\bSt\.\s"#, "saint "),
            (#"\bapprox\.\s"#, "approximately "),
        ]
        for (pattern, spoken) in abbreviations {
            s = replace(s, pattern, spoken)
        }

        // Identifiers: snake_case becomes spaces.
        s = replace(s, #"(\w)_(\w)"#, "$1 $2")

        // Dashes used as pauses become commas; ellipses become periods.
        s = replace(s, #"[ \t]+[—–-]{1,3}[ \t]+"#, ", ")
        s = replace(s, #"(\.{3,}|…)"#, ".")

        // Leftover noise with no spoken value. Newlines survive for the
        // chunker to convert into pauses.
        s = replace(s, #"([!?])[!?]+"#, "$1")
        s = replace(s, #"[|<>{}\\^~`*#@$%&_=+]"#, " ")
        s = replace(s, #"[ \t]{2,}"#, " ")
        s = replace(s, #"[ \t]+([.,!?;:])"#, "$1")
        s = replace(s, #"(?m)^[ \t]+|[ \t]+$"#, "")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            // Markdown separator rows: only pipes, dashes, colons, spaces.
            if line.range(of: #"^\s*\|?[\s:|\-]+\|?\s*$"#, options: .regularExpression) != nil,
               line.contains("-"), line.contains("|") {
                continue
            }
            let isPipeRow = line.contains("|")
            let isTabRow = line.contains("\t")
            guard isPipeRow || isTabRow else {
                result.append(line)
                continue
            }
            let separator = isPipeRow ? "|" : "\t"
            let cells = line
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            var row = cells.joined(separator: ", ")
            if let last = row.last, !".!?".contains(last) {
                row += "."
            }
            result.append(row)
        }
        return result.joined(separator: "\n")
    }

    private static func replace(
        _ text: String,
        _ pattern: String,
        _ template: String,
        caseInsensitive: Bool = false
    ) -> String {
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        return text.replacingOccurrences(of: pattern, with: template, options: options)
    }

    // Regex replacement with a Swift closure building the spoken form.
    // groups[0] is the whole match; missing groups come through as "".
    private static func replaceMatches(
        _ text: String,
        _ pattern: String,
        _ transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let full = NSRange(text.startIndex ..< text.endIndex, in: text)
        var result = ""
        var cursor = text.startIndex
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, let range = Range(match.range, in: text) else { return }
            var groups: [String] = []
            for i in 0 ..< match.numberOfRanges {
                if let r = Range(match.range(at: i), in: text) {
                    groups.append(String(text[r]))
                } else {
                    groups.append("")
                }
            }
            result += text[cursor ..< range.lowerBound]
            result += transform(groups)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
