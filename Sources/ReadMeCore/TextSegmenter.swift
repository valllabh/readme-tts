import Foundation

// Splits a large selection into segments at natural breaks so normalization
// and chunking happen incrementally: a small first segment starts speech
// almost immediately and the rest is processed while audio plays. Paragraph
// breaks are safe split points because no normalizer rule crosses a blank
// line; plain line breaks and spaces are fallbacks.
public enum TextSegmenter {
    public static let firstSegmentMax = 2048
    public static let segmentMax = 16384

    public static func segments(of text: String) -> [String] {
        guard text.count > firstSegmentMax else { return [text] }
        var result: [String] = []
        var remaining = Substring(text)
        var limit = firstSegmentMax

        while remaining.count > limit {
            let window = remaining.prefix(limit)
            let cut = window.range(of: "\n\n", options: .backwards)?.upperBound
                ?? window.range(of: "\n", options: .backwards)?.upperBound
                ?? window.range(of: " ", options: .backwards)?.upperBound
                ?? window.endIndex
            // Guarantee progress even when the only break is at the start.
            let end = cut > remaining.startIndex ? cut : window.endIndex
            result.append(String(remaining[..<end]))
            remaining = remaining[end...]
            limit = segmentMax
        }
        if !remaining.isEmpty {
            result.append(String(remaining))
        }
        return result
    }
}
