import AppKit

// The menu bar face of the app: a speech bubble matching the app icon
// (scripts/makeicon.swift), drawn as a template image so it adapts to
// light and dark menu bars. Three states mirror the old SF symbol trio:
// idle outline, speaking filled with waveform bars, paused filled with
// pause bars.
enum StatusGlyph {
    enum State {
        case idle
        case speaking(phase: Int)
        case paused
    }

    // Equalizer frames cycled while speaking, so a muted Mac still shows
    // that reading is in progress.
    private static let speakingHeights: [[CGFloat]] = [
        [3.5, 6.5, 3.5],
        [5.0, 4.5, 5.5],
        [6.5, 3.0, 5.0],
        [4.0, 5.5, 3.0],
        [6.0, 4.0, 6.5],
        [3.0, 7.0, 4.5],
    ]

    static var speakingFrameCount: Int { speakingHeights.count }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ state: State) {
        let bubble = silhouette()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        switch state {
        case .idle:
            bubble.lineWidth = 1.4
            bubble.stroke()
            fillBars(knockout: false)
        case .speaking(let phase):
            bubble.fill()
            fillBars(knockout: true, heights: speakingHeights[phase % speakingHeights.count])
        case .paused:
            bubble.fill()
            fillPause()
        }
    }

    // Bubble body united with its tail so the outline strokes as one shape.
    private static func silhouette() -> NSBezierPath {
        let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: 16, height: 11.5), xRadius: 3.6, yRadius: 3.6)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 3.9, y: 6.5))
        tail.line(to: NSPoint(x: 4.6, y: 1.6))
        tail.line(to: NSPoint(x: 8.4, y: 5.6))
        tail.close()
        return NSBezierPath(cgPath: body.cgPath.union(tail.cgPath))
    }

    private static func fillBars(knockout: Bool, heights: [CGFloat] = [3.5, 6.5, 3.5]) {
        withBlend(knockout: knockout) {
            let barW: CGFloat = 2, gap: CGFloat = 1.6
            let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
            var x = 9 - total / 2
            for h in heights {
                let bar = NSRect(x: x, y: 10.75 - h / 2, width: barW, height: h)
                NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2).fill()
                x += barW + gap
            }
        }
    }

    private static func fillPause() {
        withBlend(knockout: true) {
            for x in [5.7, 10.1] as [CGFloat] {
                let bar = NSRect(x: x, y: 8, width: 2.2, height: 5.5)
                NSBezierPath(roundedRect: bar, xRadius: 1.1, yRadius: 1.1).fill()
            }
        }
    }

    private static func withBlend(knockout: Bool, _ body: () -> Void) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        if knockout { cg.setBlendMode(.clear) }
        body()
        cg.restoreGState()
    }
}
