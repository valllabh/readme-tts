import Foundation

// Validates LLM polish output against its input. Small models fail in
// specific ways, each seen live: chat replies to junk, duplication with
// garbage joints, fabricated URLs, foreign script fragments, dot spam.
// Every check here exists because one of those reached the speakers.
public enum PolishValidator {
    public enum Verdict: Equatable {
        case ok(String)
        case rejected(reason: String)
    }

    public static func validate(input: String, rawOutput: String) -> Verdict {
        let output = sanitize(rawOutput)
        guard !output.isEmpty, output.count <= Int(Double(input.count) * 1.4) + 30 else {
            return .rejected(reason: "length")
        }
        guard sharesEnoughWords(input: input, output: output) else {
            return .rejected(reason: "drifted from input")
        }
        guard !hasLoopedRepetition(output: output, input: input) else {
            return .rejected(reason: "repetition loop")
        }
        guard !fabricatesContent(input: input, output: output) else {
            return .rejected(reason: "fabricated content")
        }
        guard !introducesForeignScript(input: input, output: output) else {
            return .rejected(reason: "foreign script")
        }
        return .ok(output)
    }

    // Chat template tokens leak into small model output and would be spoken.
    public static func sanitize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: #"<\|?[a-zA-Z0-9_]+\|?>"#,
            with: " ",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: "```", with: " ")
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // The rewrite must stay anchored to the input: most input words should
    // survive into the output. Refusals, translations, and reversed
    // gibberish all fail this cheaply.
    static func sharesEnoughWords(input: String, output: String) -> Bool {
        let inputWords = Set(words(of: input))
        guard inputWords.count >= 3 else { return true }
        let outputWords = Set(words(of: output))
        let common = inputWords.intersection(outputWords).count
        return Double(common) / Double(inputWords.count) >= 0.5
    }

    // A four word sequence appearing twice in the output but not in the
    // input means the model looped.
    static func hasLoopedRepetition(output: String, input: String) -> Bool {
        func repeatedFourgrams(_ text: String) -> Set<String> {
            let ws = words(of: text)
            guard ws.count >= 8 else { return [] }
            var seen = Set<String>()
            var repeated = Set<String>()
            for i in 0 ... (ws.count - 4) {
                let gram = ws[i ..< i + 4].joined(separator: " ")
                if !seen.insert(gram).inserted {
                    repeated.insert(gram)
                }
            }
            return repeated
        }
        let inputRepeats = repeatedFourgrams(input)
        return !repeatedFourgrams(output).subtracting(inputRepeats).isEmpty
    }

    // Words a rewrite may legitimately introduce: spoken forms of numbers,
    // symbols, and units. Anything else novel means the model made it up.
    static let spokenFormWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "first", "second",
        "third", "fourth", "fifth", "point", "dot", "slash", "dash", "at",
        "percent", "degrees", "plus", "minus", "equals", "and", "or", "to",
        "number", "hash", "colon", "comma", "star", "underscore", "letter",
        "capital", "seconds", "minutes", "minute", "hours", "hour", "days",
        "day", "dollars", "dollar", "cents", "cent", "euros", "pounds",
        "version", "the", "is", "for", "of",
    ]

    static func fabricatesContent(input: String, output: String) -> Bool {
        let inputWords = Set(words(of: input))
        let novel = Set(words(of: output))
            .subtracting(inputWords)
            .subtracting(spokenFormWords)
        return novel.count > max(1, inputWords.count / 5)
    }

    // Output in a script the input never used is hallucination.
    static func introducesForeignScript(input: String, output: String) -> Bool {
        func hasForeign(_ s: String) -> Bool {
            s.unicodeScalars.contains { scalar in
                let v = scalar.value
                return (0x0400 ... 0x04FF).contains(v)   // Cyrillic
                    || (0x0600 ... 0x06FF).contains(v)   // Arabic
                    || (0x3040 ... 0x30FF).contains(v)   // Kana
                    || (0x4E00 ... 0x9FFF).contains(v)   // CJK
                    || (0xAC00 ... 0xD7AF).contains(v)   // Hangul
            }
        }
        return hasForeign(output) && !hasForeign(input)
    }

    private static func words(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
