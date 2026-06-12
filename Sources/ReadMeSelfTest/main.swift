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

expectEqual(
    TextNormalizer.normalize("He said hello [Music] and left (laughs) quickly."),
    "He said hello and left quickly.",
    "normalizer: caption markers dropped"
)

// CVE style identifiers are separators with comma pauses, never "to" ranges;
// year pairs stay ranges. This is the fix for the CVE table read that sent
// nonsense number runs to the TTS and made it hallucinate.
expectEqual(
    TextNormalizer.normalize("Patched in CVE-2026-33827 today."),
    "Patched in CVE twenty twenty six, three three eight two seven today.",
    "normalizer: id hyphens read as pauses not ranges"
)

expectEqual(
    TextNormalizer.normalize("From 1999-2026 it grew."),
    "From nineteen ninety nine to twenty twenty six it grew.",
    "normalizer: year pairs stay ranges"
)

expectEqual(
    TextNormalizer.normalize("DescriptionSeverityType columns."),
    "Description Severity Type columns.",
    "normalizer: jammed table cells split at case boundaries"
)

expectEqual(
    TextNormalizer.normalize("Before\u{FFFC} and\u{200B} after."),
    "Before and after.",
    "normalizer: invisible placeholders stripped"
)

// Number dense text (the CVE table failure) gets much shorter chunks so
// each generation call re-anchors the model before it can drift.
do {
    let row = "CVE twenty twenty six, three three eight two seven Critical Remote Code Execution tcpip sys NULL deref CVE twenty twenty six, four zero four one three Important Denial of Service"
    let dense = TextNormalizer.normalize(Array(repeating: row, count: 4).joined(separator: " "))
    let denseChunks = SentenceChunker.chunks(for: dense)
    expect(
        denseChunks.allSatisfy { $0.text.count <= SentenceChunker.denseChunkMax + 10 },
        "chunker: dense text capped at short chunks (max \(denseChunks.map(\.text.count).max() ?? 0))"
    )

    let prose = Array(
        repeating: "The pipeline takes a code base and emits validated findings with evidence attached.",
        count: 10
    ).joined(separator: " ")
    let proseChunks = SentenceChunker.chunks(for: prose)
    expect(
        proseChunks.contains { $0.text.count > SentenceChunker.denseChunkMax },
        "chunker: normal prose keeps full size chunks"
    )

    // The exact live escape: a CVE table mid article, surrounded by enough
    // prose that block level density stayed under threshold while the table
    // chunks themselves were pure number soup. Density is per piece now.
    let article = "Across the Windows network stack and adjacent services, this Patch Tuesday includes sixteen CVEs our engineering teams found using the new scanning harness, listed in the table below with severity and class. "
        + Array(repeating: row, count: 6).joined(separator: " ")
        + " Let us take a closer look at two of the findings and what made them hard for a single model to see."
    let mixed = SentenceChunker.chunks(for: TextNormalizer.normalize(article))
    let longDense = mixed.filter { chunk in
        chunk.text.count > SentenceChunker.denseChunkMax + 10
            && chunk.text.lowercased().contains("four zero four")
    }
    expect(
        longDense.isEmpty,
        "chunker: table inside prose still gets short chunks (\(longDense.count) escaped)"
    )
}

// HTML pasteboard flavor: structure survives where the plain flavor
// flattens it. Headings separate from body with a paragraph break, images
// vanish, table rows become tab rows the normalizer reads as sentences.
expectEqual(
    HTMLTextExtractor.text(fromHTML: "<h2>Patch Tuesday cohort</h2><p>Across the network stack we found bugs.</p>"),
    "Patch Tuesday cohort\n\nAcross the network stack we found bugs.",
    "html: heading separates from body"
)

expectEqual(
    HTMLTextExtractor.text(fromHTML: "<p>Before.</p><figure><img src=\"x.png\" alt=\"diagram\"><figcaption>Figure 1: flow</figcaption></figure><p>After.</p>"),
    "Before.\n\nFigure 1: flow\n\nAfter.",
    "html: images dropped, captions kept as own line"
)

expectEqual(
    HTMLTextExtractor.text(fromHTML: "<table><tr><td>Component</td><td>Severity</td></tr><tr><td>tcpip</td><td>Critical</td></tr></table>"),
    "Component\tSeverity\n\ntcpip\tCritical",
    "html: table cells become tab rows"
)

expectEqual(
    HTMLTextExtractor.text(fromHTML: "<script>var x = 1;</script><p>Q&amp;A at 5&nbsp;pm &#8212; bring &lt;ideas&gt;.</p><style>p{}</style>"),
    "Q&A at 5 pm \u{2014} bring <ideas>.",
    "html: scripts and styles dropped, entities decoded"
)

expectEqual(
    HTMLTextExtractor.text(fromHTML: "<ul>\n  <li>First point</li>\n  <li>Second point</li>\n</ul>"),
    "First point\n\nSecond point",
    "html: list items on own lines, source newlines ignored"
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

// MARK: - PolishValidator

do {
    let input = "The quarterly report shows steady growth across all regions."
    let good = "The quarterly report shows steady growth across all regions."
    expect(PolishValidator.validate(input: input, rawOutput: good) == .ok(good), "validator: clean output passes")

    expect(
        PolishValidator.validate(input: "Sauteed for 3m 55s", rawOutput: "Sauteed for 3m 55s https://paste.org/12345678/") ==
            .rejected(reason: "fabricated content"),
        "validator: fabricated url rejected"
    )

    expect(
        PolishValidator.validate(input: input, rawOutput: good + " ний") ==
            .rejected(reason: "foreign script"),
        "validator: foreign script rejected"
    )

    let looped = "smaller TTS model would cost voice quality. ieux TTS model would cost voice quality."
    expect(
        PolishValidator.validate(input: "smaller TTS model would cost voice quality.", rawOutput: looped) ==
            .rejected(reason: "repetition loop"),
        "validator: repetition loop rejected"
    )

    expectEqual(
        PolishValidator.sanitize("Hello there<end_of_turn><end_of_turn>"),
        "Hello there",
        "validator: template tokens stripped"
    )
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
