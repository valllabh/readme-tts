import Foundation
import NaturalLanguage

// One unit of speech generation plus the silence to insert after it. The
// model itself does not pause at line or paragraph breaks (newlines never
// reach it), so structural pauses are injected as real silence by the player.
public struct SpeechChunk: Equatable {
    public let text: String
    public let pauseAfter: Double

    public init(text: String, pauseAfter: Double) {
        self.text = text
        self.pauseAfter = pauseAfter
    }
}

// Splits normalized text into bounded chunks for generation. Marvis caps each
// generation call at 60 seconds of audio and aborts on overlong inputs (it
// only splits on newlines internally), so every chunk must stay well under
// that limit. Chunk boundaries fall on sentence ends where possible.
public enum SentenceChunker {
    public static let chunkMax = 500

    // Number and acronym dense text (ID tables, spec sheets, CVE lists) sits
    // far off the conversational distribution Marvis was trained on, and
    // autoregressive drift compounds within one generation call. Much
    // shorter chunks re-anchor the model on a fresh call before it can
    // wander into hallucinated phonemes.
    public static let denseChunkMax = 160

    public static let sentenceGapPause = 0.15
    public static let lineBreakPause = 0.5
    public static let paragraphPause = 0.9

    public static func chunks(for text: String) -> [SpeechChunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [SpeechChunk] = []
        let paragraphs = trimmed
            .replacingOccurrences(of: "\n{2,}", with: "\u{2029}", options: .regularExpression)
            .components(separatedBy: "\u{2029}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for paragraph in paragraphs {
            let blocks = joinWrappedLines(paragraph)
            for (blockIndex, block) in blocks.enumerated() {
                let isLastBlock = blockIndex == blocks.count - 1
                let blockPause = isLastBlock ? paragraphPause : lineBreakPause
                let pieces = boundedPieces(for: block)
                for (pieceIndex, piece) in pieces.enumerated() {
                    let isLastPiece = pieceIndex == pieces.count - 1
                    result.append(SpeechChunk(
                        text: piece,
                        pauseAfter: isLastPiece ? blockPause : sentenceGapPause
                    ))
                }
            }
        }

        // Chunks with no letters or digits (leftover punctuation, separator
        // debris) are unspeakable and would confuse the polish model.
        result = result.filter { chunk in
            chunk.text.contains { $0.isLetter || $0.isNumber }
        }

        // No trailing silence after the final chunk.
        if let last = result.last {
            result[result.count - 1] = SpeechChunk(text: last.text, pauseAfter: 0)
        }
        return result
    }

    // Single line breaks are ambiguous: PDF style wrapping mid sentence, or a
    // real break (list item, chat line). PDFs hard wrap every visual line, so
    // joins are decided per line pair and hyphenated word splits are healed.
    // Page number artifacts are dropped entirely.
    private static func joinWrappedLines(_ paragraph: String) -> [String] {
        let lines = paragraph
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isPageArtifact($0) }

        var blocks: [String] = []
        var current = ""
        for line in lines {
            if current.isEmpty {
                current = line
                continue
            }
            if isHyphenWrap(previous: current, next: line) {
                current = String(current.dropLast()) + line
            } else if shouldJoin(previous: current, next: line) {
                current += " " + line
            } else {
                blocks.append(current)
                current = line
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }
        return blocks
    }

    // Page numbers and "Page N of M" furniture that rides along in PDF
    // selections. Spoken, these inject random numbers mid sentence.
    private static func isPageArtifact(_ line: String) -> Bool {
        line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil
            || line.range(of: #"^[Pp]age \d+( of \d+)?$"#, options: .regularExpression) != nil
    }

    // A word split across lines: "infor-" then "mation flows". Joined with
    // the hyphen removed so it reads as one word.
    private static func isHyphenWrap(previous: String, next: String) -> Bool {
        guard previous.count > 1, previous.hasSuffix("-") else { return false }
        let beforeHyphen = previous[previous.index(previous.endIndex, offsetBy: -2)]
        let firstNext = next.first ?? " "
        return beforeHyphen.isLetter && firstNext.isLetter && firstNext.isLowercase
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        guard let last = previous.last else { return false }
        // Sentence ended: real break.
        if ".!?…".contains(last) { return false }
        // Clause continues across the wrap.
        if ",;:".contains(last) { return true }
        // No punctuation at all: lowercase continuation is a wrap.
        if next.first?.isLowercase == true { return true }
        // Uppercase next is ambiguous (proper noun mid sentence vs list
        // item). Long unpunctuated lines are PDF wraps; short ones are list
        // items or headings.
        return previous.count > 40
    }

    private static func boundedPieces(for block: String) -> [String] {
        let max = isDense(block) ? denseChunkMax : chunkMax
        var result: [String] = []
        var current = ""
        for sentence in splitSentences(block) {
            for piece in splitLongSentence(sentence, max: max) {
                if current.isEmpty {
                    current = piece
                } else if current.count + piece.count + 1 <= max {
                    current += " " + piece
                } else {
                    result.append(current)
                    current = piece
                }
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    // Spelled out number words from the normalizer, plus point and oh.
    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "point", "oh",
    ]

    // Dense means over thirty percent of tokens are number words, raw
    // digits, or short all caps acronyms. Runs on normalized text, where
    // digits are already spelled out.
    static func isDense(_ text: String) -> Bool {
        let tokens = text.split { !$0.isLetter && !$0.isNumber }
        guard tokens.count >= 8 else { return false }
        let weird = tokens.filter { token in
            numberWords.contains(token.lowercased())
                || token.contains(where: \.isNumber)
                || (token.count >= 2 && token.count <= 6 && token.allSatisfy(\.isUppercase))
        }.count
        return Double(weird) / Double(tokens.count) > 0.3
    }

    private static func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private static func splitLongSentence(_ sentence: String, max: Int) -> [String] {
        guard sentence.count > max else { return [sentence] }
        // Prefer clause boundaries, then spaces, then a hard cut.
        var pieces: [String] = []
        var remaining = Substring(sentence)
        while remaining.count > max {
            let window = remaining.prefix(max)
            let cut = window.lastIndex(where: { ",;:".contains($0) })
                ?? window.lastIndex(of: " ")
                ?? window.endIndex
            let end = cut == window.endIndex ? window.endIndex : remaining.index(after: cut)
            let piece = remaining[remaining.startIndex ..< end].trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { break }
            pieces.append(piece)
            remaining = remaining[end...]
        }
        let tail = remaining.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            pieces.append(tail)
        }
        return pieces
    }
}
