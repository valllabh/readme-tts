import Foundation
import ReadMeCore

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS \(label)")
    } else {
        print("FAIL \(label)")
        failures += 1
    }
}

func expectEqual(_ actual: String, _ expected: String, _ label: String) {
    if actual == expected {
        print("PASS \(label)")
    } else {
        print("FAIL \(label)\n  expected: \(expected)\n  actual:   \(actual)")
        failures += 1
    }
}

// MARK: - SentenceChunker

expect(SentenceChunker.chunks(for: "   \n  ").isEmpty, "chunker: empty text")

do {
    let chunks = SentenceChunker.chunks(for: "One. Two. Three.")
    expect(chunks.count == 1, "chunker: short text stays one chunk")
    expect(chunks.last?.pauseAfter == 0, "chunker: no trailing pause")
}

do {
    let chunks = SentenceChunker.chunks(for: "Para one ends here.\n\nPara two starts here.")
    expect(chunks.count == 2, "chunker: paragraphs split")
    expect(chunks[0].pauseAfter == SentenceChunker.paragraphPause, "chunker: paragraph break pause")
}

do {
    let chunks = SentenceChunker.chunks(for: "Item one\nItem two\nItem three")
    expect(chunks.count == 3, "chunker: list lines stay separate")
    expect(chunks[0].pauseAfter == SentenceChunker.lineBreakPause, "chunker: line break pause")
}

do {
    let chunks = SentenceChunker.chunks(for: "A line\nwrapped sentence ends here. Next one.")
    expect(chunks.count == 1, "chunker: wrapped line joins")
    expect(chunks[0].text.hasPrefix("A line wrapped sentence ends here."), "chunker: wrap join content")
}

do {
    let sentence = "Each of these sentences has enough words to take up meaningful space in a chunk. "
    let chunks = SentenceChunker.chunks(for: String(repeating: sentence, count: 20))
    expect(chunks.count > 1, "chunker: long text splits")
    expect(chunks.allSatisfy { $0.text.count <= SentenceChunker.chunkMax }, "chunker: all chunks under cap")
    expect(chunks[0].pauseAfter == SentenceChunker.sentenceGapPause, "chunker: sentence gap pause inside block")
}

do {
    let clause = "this clause keeps going and going with many words"
    let text = Array(repeating: clause, count: 16).joined(separator: ", ") + "."
    let chunks = SentenceChunker.chunks(for: text)
    expect(chunks.count > 1, "chunker: giant sentence splits at clauses")
    expect(chunks.allSatisfy { $0.text.count <= SentenceChunker.chunkMax }, "chunker: clause pieces under cap")
}

// PDF style selections: comma wraps, hyphen splits, page numbers.
do {
    let chunks = SentenceChunker.chunks(for: "first part of the sentence,\nsecond part ends here.")
    expect(chunks.count == 1, "chunker: comma wrap joins")
}

do {
    let chunks = SentenceChunker.chunks(for: "all of the infor-\nmation flows through.")
    expect(chunks.count == 1 && chunks[0].text.contains("information"), "chunker: hyphen split heals")
}

do {
    let chunks = SentenceChunker.chunks(for: "text continues here\n42\nmore lowercase text follows.")
    expect(chunks.count == 1 && !chunks[0].text.contains("42"), "chunker: page number dropped")
}

do {
    let text = "the committee presented its annual findings to the\nUnited States Congress last week."
    let chunks = SentenceChunker.chunks(for: text)
    expect(chunks.count == 1, "chunker: long unpunctuated wrap joins before uppercase")
}

// MARK: - TextNormalizer

expectEqual(
    TextNormalizer.normalize("Revenue grew 25% to $3,000 in Q2."),
    "Revenue grew twenty five percent to three thousand dollars in Q2.",
    "normalizer: percent and currency"
)

expectEqual(
    TextNormalizer.normalize("See [the docs](https://example.com/a/b) for info."),
    "See the docs for info.",
    "normalizer: markdown link keeps label"
)

expectEqual(
    TextNormalizer.normalize("Visit https://www.example.com/path?q=1 today."),
    "Visit example dot com today.",
    "normalizer: bare url becomes spoken host"
)

expectEqual(
    TextNormalizer.normalize("Mail vallabh.joshi@gmail.com now."),
    "Mail vallabh dot joshi at gmail dot com now.",
    "normalizer: email reads naturally"
)

expectEqual(
    TextNormalizer.normalize("**Bold** and *italic* and `inline_code` here."),
    "Bold and italic and inline code here.",
    "normalizer: markdown emphasis and code"
)

expectEqual(
    TextNormalizer.normalize("## Heading\n- bullet one\n- bullet two"),
    "Heading\nbullet one\nbullet two",
    "normalizer: headers and bullets"
)

expectEqual(
    TextNormalizer.normalize("Cache hit -> fast path, e.g. under 5ms."),
    "Cache hit to fast path, for example, under five milliseconds.",
    "normalizer: arrows abbreviations units"
)

expectEqual(
    TextNormalizer.normalize("Use snake_case and read/write modes."),
    "Use snake case and read or write modes.",
    "normalizer: identifiers and slashes"
)

expectEqual(
    TextNormalizer.normalize("Wait... what?! Really??"),
    "Wait. what? Really?",
    "normalizer: ellipses and repeated punctuation"
)

expectEqual(
    TextNormalizer.normalize("Meet at 9:05pm on the 21st."),
    "Meet at nine oh five p m on the twenty first.",
    "normalizer: time and ordinal"
)

expectEqual(
    TextNormalizer.normalize("Pi is 3.14, founded in 1984, build 2026."),
    "Pi is three point one four, founded in nineteen eighty four, build twenty twenty six.",
    "normalizer: decimal and years"
)

expectEqual(
    TextNormalizer.normalize("| Name | Role |\n|---|---|\n| VJ | Architect |"),
    "Name, Role.\nVJ, Architect.",
    "normalizer: markdown table rows"
)

expectEqual(
    TextNormalizer.normalize("Name\tRole\nVJ\tArchitect"),
    "Name, Role.\nVJ, Architect.",
    "normalizer: tab separated table rows"
)

expectEqual(
    TextNormalizer.normalize("Note: state-of-the-art results; really (very) good — truly."),
    "Note, state of the art results, really, very, good, truly.",
    "normalizer: colon semicolon parens hyphen dash read as pauses"
)

expectEqual(
    TextNormalizer.normalize("Takes 3-5 days on a 16:9 screen [citation needed]."),
    "Takes three to five days on a sixteen to nine screen, citation needed.",
    "normalizer: ranges ratios brackets"
)

// Separator lines and decorative marks produce no chunks.
do {
    let text = "first scenario reads fine.  ✔ Goal\n---\nsecond scenario also reads.  ✔\n---"
    let chunks = SentenceChunker.chunks(for: TextNormalizer.normalize(text))
    expect(chunks.count == 2, "pipeline: separators produce no junk chunks")
    expect(chunks.allSatisfy { !$0.text.contains("-") && !$0.text.contains("✔") }, "pipeline: marks stripped")
}

do {
    let chunks = SentenceChunker.chunks(for: TextNormalizer.normalize("===\n***\n- - -"))
    expect(chunks.isEmpty, "pipeline: separator only selection yields nothing")
}

// MARK: - TextSegmenter

do {
    let small = "Short text stays whole."
    expect(TextSegmenter.segments(of: small) == [small], "segmenter: small text single segment")

    let para = "First paragraph with enough words to mean something real here.\n\n"
    let big = String(repeating: para, count: 200)
    let segments = TextSegmenter.segments(of: big)
    expect(segments.count > 1, "segmenter: large text splits")
    expect(segments.joined() == big, "segmenter: nothing lost")
    expect(segments[0].count <= TextSegmenter.firstSegmentMax, "segmenter: small first segment")
    expect(segments[0].hasSuffix("\n\n"), "segmenter: splits at paragraph boundary")
    expect(segments.dropFirst().dropLast().allSatisfy { $0.count <= TextSegmenter.segmentMax },
           "segmenter: later segments bounded")
}

// MARK: - SelectionSignature

do {
    let a = "The quick brown fox jumps over the lazy dog near the river bank today."
    expect(SelectionSignature.make(a) == SelectionSignature.make(a), "signature: stable")
    expect(SelectionSignature.make(a) != SelectionSignature.make(a + " More."), "signature: tail change detected")
    expect(SelectionSignature.make(a) != SelectionSignature.make("New start. " + a), "signature: head change detected")
    let mid = a.replacingOccurrences(of: "jumps", with: "leaps")
    expect(SelectionSignature.make(a) != SelectionSignature.make(mid) || a.count != mid.count,
           "signature: same length middle edit covered by head tail or length")
}

if failures > 0 {
    print("\(failures) failure(s)")
    exit(1)
}
print("all tests passed")

// MARK: - Pipeline benchmark (runs when READMEBENCH=1)

if ProcessInfo.processInfo.environment["READMEBENCH"] == "1" {
    let sample = """
    Revenue grew 25% to $3,000 in Q2, e.g. the API tier added 1,200 users. \
    See https://example.com/report for details. The committee presented its \
    annual findings last week. Next review is at 9:05pm on the 21st.

    | Plan | Users |
    |---|---|
    | Free | 8,500 |

    More prose follows with normal sentences. Some of them wrap across
    lines like a PDF would, and the pipeline needs to heal all of it.

    """
    for factor in [8, 80, 800] {
        let text = String(repeating: sample, count: factor)
        let start = Date()
        let chunks = SentenceChunker.chunks(for: TextNormalizer.normalize(text))
        let ms = Date().timeIntervalSince(start) * 1000
        print(String(format: "bench: %6d KB -> %4d chunks in %8.1f ms", text.count / 1024, chunks.count, ms))
    }
}
