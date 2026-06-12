import Foundation

// Turns the HTML pasteboard flavor of a web selection into structured plain
// text. The AX selected text and plain string flavors flatten the page:
// headings glue to body text, figures leak caption fragments, tables lose
// their rows. HTML keeps the structure, so blocks become newlines (which
// SentenceChunker turns into real pauses), table cells become tab rows
// (which TextNormalizer reads as comma separated sentences), and images
// disappear entirely.
public enum HTMLTextExtractor {
    public static func text(fromHTML html: String) -> String {
        var s = html.replacingOccurrences(of: "\r\n", with: "\n")

        // Invisible machinery and non text content go first, including the
        // content between the tags.
        s = replace(s, #"(?is)<(script|style|head|noscript|svg|iframe|object|video|audio|canvas)\b[^>]*>.*?</\1>"#, " ")
        s = replace(s, #"(?s)<!--.*?-->"#, " ")

        // Images never speak; the figure caption text survives as its own
        // block below.
        s = replace(s, #"(?i)<img\b[^>]*/?>"#, " ")

        // Source HTML newlines are formatting, not structure; structure
        // comes from the tags converted below.
        s = replace(s, #"[\n\t]+"#, " ")

        // Headings stand alone as paragraphs so a real pause separates them
        // from the body.
        s = replace(s, #"(?i)<h[1-6][^>]*>"#, "\n\n")
        s = replace(s, #"(?i)</h[1-6]>"#, "\n\n")

        // Table cells separate with tabs and rows with newlines; the
        // normalizer's tab table rule reads each row as a comma sentence.
        s = replace(s, #"(?i)</t[dh]>"#, "\t")
        s = replace(s, #"(?i)</tr>"#, "\n")

        // Block boundaries become line breaks.
        s = replace(s, #"(?i)<br[^>]*>"#, "\n")
        s = replace(
            s,
            #"(?i)</?(p|div|li|ul|ol|table|thead|tbody|tfoot|tr|section|article|header|footer|figure|figcaption|blockquote|pre|main|aside|nav|dl|dt|dd)\b[^>]*>"#,
            "\n"
        )

        // Remaining tags are inline; their text flows on.
        s = replace(s, #"<[^>]+>"#, "")

        s = decodeEntities(s)

        // Whitespace discipline: collapse spaces, tidy tab cell separators,
        // trim around line breaks, cap blank runs at one empty line.
        s = replace(s, #"[ \x{00A0}]+"#, " ")
        s = replace(s, #" *\t[ \t]*"#, "\t")
        s = replace(s, #"\t+\n"#, "\n")
        s = replace(s, #"[ \t]*\n[ \t]*"#, "\n")
        s = replace(s, #"\n{3,}"#, "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "mdash": "\u{2014}", "ndash": "\u{2013}",
        "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "copy": "\u{00A9}",
        "reg": "\u{00AE}", "trade": "\u{2122}", "middot": "\u{00B7}",
        "bull": "\u{2022}", "deg": "\u{00B0}", "times": "\u{00D7}",
    ]

    private static func decodeEntities(_ text: String) -> String {
        replaceMatches(text, #"&(#x?[0-9a-fA-F]+|[a-zA-Z]+);"#) { groups in
            let body = groups[1]
            if body.hasPrefix("#") {
                let hex = body.lowercased().hasPrefix("#x")
                let digits = String(body.dropFirst(hex ? 2 : 1))
                if let value = UInt32(digits, radix: hex ? 16 : 10),
                   let scalar = Unicode.Scalar(value) {
                    return String(Character(scalar))
                }
                return ""
            }
            return namedEntities[body] ?? groups[0]
        }
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

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
            result += text[cursor ..< range.lowerBound]
            var groups: [String] = []
            for i in 0 ..< match.numberOfRanges {
                if let r = Range(match.range(at: i), in: text) {
                    groups.append(String(text[r]))
                } else {
                    groups.append("")
                }
            }
            result += transform(groups)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
